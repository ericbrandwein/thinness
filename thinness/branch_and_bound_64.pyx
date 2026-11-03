"""Branch and bound for graphs of at most 64 vertices, where every set of vertices or parts is a 64-bit word.

It is the same search as the one in `branch_and_bound`, which works for graphs
of any size, function by function.
"""
from libc.stdint cimport uint64_t
from sage.graphs.graph import Graph
from cysignals.memory cimport sig_malloc, sig_calloc, sig_free
from cysignals.signals cimport sig_on, sig_off

from thinness.seen_states cimport SeenStates

MAX_VERTICES = 64


cdef extern from *:
    int __builtin_ctzll(unsigned long long) nogil
    int __builtin_popcountll(unsigned long long) nogil


def search(
    graph: Graph,
    int lower_bound,
    int upper_bound,
    int max_prefix_length,
    int max_seen_entries,
) -> tuple[int, list[int], list[int]]:
    """Search for a solution with at most `upper_bound` parts, stopping at one with at most `lower_bound`.

    The vertices of `graph` must be 0, ..., n-1, with n at most 64. Returns the
    number of parts of the best solution found, or -1 if none was found, and the
    order and the part of each vertex of that solution.
    """
    cdef _Context ctx = _Context(graph, upper_bound, max_prefix_length, max_seen_entries)

    sig_on()
    cdef int solution = _branch_and_bound(
        ctx,
        suffix_vertices=_lower_bits(ctx.n),
        level=0,
        parts_used=0,
        lower_bound=lower_bound,
        upper_bound=upper_bound,
    )
    sig_off()

    return (
        solution,
        [ctx.best_order[i] for i in range(ctx.n)],
        [ctx.best_partition[i] for i in range(ctx.n)],
    )


cdef class _Context:
    """State shared by every call of the branch and bound recursion.

    The arrays with one row per prefix length (`*_suffix_neighbors`,
    `parts_for_vertices` and `vertices_not_added`) let each node of the search
    keep its own rows while its children run.
    """
    cdef int n
    cdef uint64_t* graph
    cdef int* prefix
    cdef int* part_of
    cdef int max_parts
    cdef uint64_t* part_neighbors
    cdef uint64_t* vertex_suffix_neighbors
    cdef uint64_t* part_suffix_neighbors
    cdef uint64_t* parts_for_vertices
    cdef uint64_t* vertices_not_added
    cdef uint64_t* unlockers
    cdef uint64_t canonical_vertices
    cdef SeenStates seen_states
    cdef int* best_order
    cdef int* best_partition
    cdef int max_prefix_length

    def __cinit__(
        self,
        graph: Graph,
        int max_parts,
        int max_prefix_length,
        int max_seen_entries,
    ):
        cdef int n = graph.order()
        if n > MAX_VERTICES or max_parts > MAX_VERTICES:
            raise ValueError(f'Graphs must have at most {MAX_VERTICES} vertices')
        self.n = n
        self.max_parts = max_parts

        self.graph = <uint64_t*>sig_calloc(n, sizeof(uint64_t))
        self.prefix = <int*>sig_calloc(n, sizeof(int))
        self.part_of = <int*>sig_calloc(n, sizeof(int))
        # At least one, so that they are not NULL when there are no parts.
        self.part_neighbors = <uint64_t*>sig_calloc(max_parts + 1, sizeof(uint64_t))
        # One more level for the suffix neighbors, as the greedy step of a node starts with them.
        self.vertex_suffix_neighbors = <uint64_t*>sig_calloc((n + 1) * n, sizeof(uint64_t))
        self.part_suffix_neighbors = <uint64_t*>sig_calloc((n + 1) * max_parts + 1, sizeof(uint64_t))
        self.parts_for_vertices = <uint64_t*>sig_calloc(n * n, sizeof(uint64_t))
        self.vertices_not_added = <uint64_t*>sig_calloc(n, sizeof(uint64_t))
        self.unlockers = <uint64_t*>sig_calloc(n, sizeof(uint64_t))
        self.best_order = <int*>sig_calloc(n, sizeof(int))
        self.best_partition = <int*>sig_calloc(n, sizeof(int))
        if (
            self.graph == NULL or self.prefix == NULL or self.part_of == NULL
            or self.part_neighbors == NULL or self.vertex_suffix_neighbors == NULL
            or self.part_suffix_neighbors == NULL or self.parts_for_vertices == NULL
            or self.vertices_not_added == NULL or self.unlockers == NULL
            or self.best_order == NULL or self.best_partition == NULL
        ):
            raise MemoryError

        for u, v in graph.edge_iterator(labels=False):
            self.graph[u] |= _bit(v)
            self.graph[v] |= _bit(u)

        self.seen_states = SeenStates(1, max_parts, max_seen_entries)

        self.canonical_vertices = 0
        cdef list orbit
        for orbit in graph.automorphism_group(orbits=True, return_group=False):
            self.canonical_vertices |= _bit(orbit[0])

        self.max_prefix_length = max_prefix_length

    def __dealloc__(self):
        sig_free(self.graph)
        sig_free(self.prefix)
        sig_free(self.part_of)
        sig_free(self.part_neighbors)
        sig_free(self.vertex_suffix_neighbors)
        sig_free(self.part_suffix_neighbors)
        sig_free(self.parts_for_vertices)
        sig_free(self.vertices_not_added)
        sig_free(self.unlockers)
        sig_free(self.best_order)
        sig_free(self.best_partition)


cdef inline uint64_t _bit(int i) noexcept:
    return (<uint64_t>1) << i


cdef inline uint64_t _lower_bits(int n) noexcept:
    """The set {0, ..., n-1}."""
    return ~(<uint64_t>0) if n == 64 else _bit(n) - 1


cdef inline int _next(uint64_t elements, int start) noexcept:
    """The smallest element that is at least `start`, or -1."""
    if start >= 64:
        return -1
    cdef uint64_t rest = elements & (~(<uint64_t>0) << start)
    return __builtin_ctzll(rest) if rest != 0 else -1


cdef inline bint _is_subset_ignoring(uint64_t subset, uint64_t superset, int vertex) noexcept:
    """Whether `subset` is a subset of `superset`, ignoring `vertex`.

    The suffix neighbors computed at a node include the vertex that is about to
    be added to the prefix, which has to be ignored when comparing them.
    """
    return subset & ~_bit(vertex) & ~superset == 0


cdef int _branch_and_bound(
    _Context ctx,
    uint64_t suffix_vertices,
    int level,
    int parts_used,
    int lower_bound,
    int upper_bound,
) noexcept:
    """Search for a solution that extends the current prefix.

    `level` is the length of the prefix. Both bounds are inclusive: only
    solutions with at most `upper_bound` parts are searched for, and the search
    stops as soon as one with at most `lower_bound` parts is found. Returns the
    number of parts of the best solution found, which is stored in
    `ctx.best_order` and `ctx.best_partition`, or -1 if none was found.
    """
    cdef int entry_level = level
    level = _increment_prefix_greedily_on_existing_parts(ctx, &suffix_vertices, level, parts_used)

    if suffix_vertices == 0 and parts_used <= upper_bound:
        _copy_array(ctx.n, ctx.prefix, ctx.best_order)
        _copy_array(ctx.n, ctx.part_of, ctx.best_partition)
        return parts_used

    # The greedy step left the suffix neighbors at the level the node started at,
    # which no ancestor uses, as they all keep theirs at shorter prefixes.
    if level != entry_level:
        _compute_suffix_neighbors(ctx, suffix_vertices, level, parts_used)

    if _check_state_seen(ctx, suffix_vertices, level, parts_used):
        return -1

    cdef int best_solution_found = -1
    if _update_best_solution(
        _branch_adding_to_existing_part(
            ctx,
            suffix_vertices,
            level,
            parts_used,
            lower_bound,
            upper_bound,
        ),
        lower_bound,
        &best_solution_found,
        &upper_bound,
    ):
        return best_solution_found

    cdef int new_part_solution
    cdef int part
    cdef int vertex
    if parts_used < upper_bound:
        parts_used += 1
        part = parts_used - 1
        lower_bound = max(lower_bound, parts_used)

        vertex = _find_vertex_without_suffix_neighbors(ctx, suffix_vertices, level)
        if vertex != -1:
            # The new part is empty, so it can take such a vertex greedily.
            ctx.prefix[level] = vertex
            ctx.part_of[vertex] = part
            new_part_solution = _branch_and_bound(
                ctx,
                suffix_vertices & ~_bit(vertex),
                level + 1,
                parts_used,
                lower_bound,
                upper_bound,
            )
        else:
            new_part_solution = _branch_adding_to_new_part(
                ctx,
                suffix_vertices,
                level,
                parts_used,
                lower_bound,
                upper_bound,
            )

        if new_part_solution != -1:
            best_solution_found = new_part_solution

    return best_solution_found


cdef inline bint _update_best_solution(
    int solution,
    int lower_bound,
    int* best_solution_found,
    int* upper_bound,
) noexcept:
    """Record `solution` if one was found and tighten `upper_bound` to look for a better one.

    Returns whether the search can stop because `solution` reaches `lower_bound`.
    """
    if solution == -1:
        return False
    best_solution_found[0] = solution
    if solution <= lower_bound:
        return True
    upper_bound[0] = solution - 1
    return False


cdef inline void _copy_array(int n, int* array_from, int* array_to) noexcept:
    cdef int i
    for i in range(n):
        array_to[i] = array_from[i]


cdef inline void _compute_suffix_neighbors(
    _Context ctx,
    uint64_t suffix_vertices,
    int level,
    int parts_used,
) noexcept:
    """Suffix neighbors of the parts and of the suffix vertices, stored at `level`."""
    cdef uint64_t* part_neighbors = ctx.part_suffix_neighbors + level * ctx.max_parts
    cdef uint64_t* vertex_neighbors = ctx.vertex_suffix_neighbors + level * ctx.n
    cdef int part
    for part in range(parts_used):
        part_neighbors[part] = ctx.part_neighbors[part] & suffix_vertices
    cdef uint64_t rest = suffix_vertices
    cdef int vertex
    while rest != 0:
        vertex = __builtin_ctzll(rest)
        rest &= rest - 1
        vertex_neighbors[vertex] = ctx.graph[vertex] & suffix_vertices


cdef inline int _branch_adding_to_existing_part(
    _Context ctx,
    uint64_t suffix_vertices,
    int level,
    int parts_used,
    int lower_bound,
    int upper_bound,
) noexcept:
    cdef uint64_t* parts_for_vertices = ctx.parts_for_vertices + level * ctx.n
    cdef uint64_t vertices_not_added = 0
    cdef int best_solution_found = -1
    cdef uint64_t rest
    cdef uint64_t other_vertices
    cdef int part
    cdef int vertex

    rest = suffix_vertices
    while rest != 0:
        vertex = __builtin_ctzll(rest)
        rest &= rest - 1
        ctx.unlockers[vertex] = 0

    rest = suffix_vertices
    while rest != 0:
        vertex = __builtin_ctzll(rest)
        rest &= rest - 1
        parts_for_vertices[vertex] = _get_available_parts_for_vertex(ctx, vertex, level, parts_used)
        if parts_for_vertices[vertex] == 0:
            vertices_not_added |= _bit(vertex)

    ctx.vertices_not_added[level] = _ignore_unlocked_vertices(
        ctx,
        level,
        suffix_vertices,
        vertices_not_added,
    )

    vertex = _next(suffix_vertices, 0)
    while vertex != -1:
        other_vertices = suffix_vertices & ~_bit(vertex)

        part = _next(parts_for_vertices[vertex], 0)
        while part != -1:
            if not _can_other_vertex_be_prepended_freely(
                ctx,
                vertex,
                part,
                level,
                other_vertices,
            ) and _update_best_solution(
                _branch_with_vertex_on_part(
                    ctx,
                    vertex,
                    part,
                    other_vertices,
                    level,
                    parts_used,
                    lower_bound,
                    upper_bound,
                ),
                lower_bound,
                &best_solution_found,
                &upper_bound,
            ):
                return best_solution_found
            part = _next(parts_for_vertices[vertex], part + 1)

        vertex = _next(suffix_vertices, vertex + 1)

    return best_solution_found


cdef inline uint64_t _get_available_parts_for_vertex(
    _Context ctx,
    int vertex,
    int level,
    int parts_used,
) noexcept:
    """Parts that `vertex` can be added to if it is the next vertex of the prefix.

    Also records in `ctx.unlockers` the vertices that `vertex` unlocks, see
    `_ignore_unlocked_vertices`.
    """
    cdef uint64_t vertex_neighbors = ctx.vertex_suffix_neighbors[level * ctx.n + vertex]
    cdef uint64_t* part_neighbors = ctx.part_suffix_neighbors + level * ctx.max_parts
    cdef int suffix_degree = __builtin_popcountll(vertex_neighbors)
    cdef uint64_t parts_for_vertex = 0
    cdef uint64_t neighbors_of_part
    cdef int part
    cdef int other_part

    for part in range(parts_used):
        neighbors_of_part = part_neighbors[part] & ~_bit(vertex)
        if neighbors_of_part & ~vertex_neighbors == 0:
            parts_for_vertex |= _bit(part)
            if __builtin_popcountll(neighbors_of_part) == suffix_degree - 1:
                ctx.unlockers[__builtin_ctzll(vertex_neighbors & ~neighbors_of_part)] |= _bit(vertex)

    for part in range(parts_used):
        if parts_for_vertex & _bit(part):
            for other_part in range(part):
                if parts_for_vertex & _bit(other_part):
                    if _is_subset_ignoring(part_neighbors[part], part_neighbors[other_part], vertex):
                        parts_for_vertex &= ~_bit(part)
                        break
                    elif _is_subset_ignoring(part_neighbors[other_part], part_neighbors[part], vertex):
                        parts_for_vertex &= ~_bit(other_part)

    return parts_for_vertex


cdef inline bint _can_other_vertex_be_prepended_freely(
    _Context ctx,
    int vertex,
    int part,
    int level,
    uint64_t suffix_vertices,
) noexcept:
    """`vertex` is not in suffix."""
    cdef uint64_t* vertex_neighbors = ctx.vertex_suffix_neighbors + level * ctx.n
    cdef uint64_t* parts_for_vertices = ctx.parts_for_vertices + level * ctx.n
    cdef uint64_t rest = suffix_vertices
    cdef int other_vertex
    while rest != 0:
        other_vertex = __builtin_ctzll(rest)
        rest &= rest - 1
        if parts_for_vertices[other_vertex] & _bit(part) and _is_subset_ignoring(
            vertex_neighbors[other_vertex],
            vertex_neighbors[vertex],
            vertex,
        ):
            parts_for_vertices[vertex] &= ~_bit(part)
            return True
    return False


cdef inline uint64_t _ignore_unlocked_vertices(
    _Context ctx,
    int level,
    uint64_t suffix_vertices,
    uint64_t vertices_not_added,
) noexcept:
    """Remove from this level's candidates the vertices that some other vertex unlocks.

    A vertex `u` unlocks `v` if `u` can be added to some part so that the part's
    suffix neighbors only gain `v`. In that case putting `u` and then `v` is
    always preferable to putting `v` next, so `v` is not branched on, neither on
    an existing part nor on a new one.

    Vertices already ignored don't unlock others, so that two vertices can't
    cause each other to be ignored. Returns `vertices_not_added` without the
    ignored vertices.
    """
    cdef uint64_t* parts_for_vertices = ctx.parts_for_vertices + level * ctx.n
    cdef uint64_t ignored_vertices = 0
    cdef uint64_t rest = suffix_vertices
    cdef int vertex
    while rest != 0:
        vertex = __builtin_ctzll(rest)
        rest &= rest - 1
        if ctx.unlockers[vertex] & ~ignored_vertices:
            ignored_vertices |= _bit(vertex)
            parts_for_vertices[vertex] = 0
    return vertices_not_added & ~ignored_vertices


cdef inline int _branch_adding_to_new_part(
    _Context ctx,
    uint64_t suffix_vertices,
    int level,
    int parts_used,
    int lower_bound,
    int upper_bound,
) noexcept:
    cdef int best_solution_found = -1
    cdef int part = parts_used - 1
    # Vertices discarded by _can_other_vertex_open_new_part_freely are removed from here.
    cdef uint64_t candidates = ctx.vertices_not_added[level]
    if level == 0:
        candidates = ctx.canonical_vertices
    cdef int vertex = _next(candidates, 0)
    while vertex != -1:
        if not _can_other_vertex_open_new_part_freely(
            ctx,
            vertex,
            level,
            &candidates,
        ) and _update_best_solution(
            _branch_with_vertex_on_part(
                ctx,
                vertex,
                part,
                suffix_vertices & ~_bit(vertex),
                level,
                parts_used,
                lower_bound,
                upper_bound,
            ),
            lower_bound,
            &best_solution_found,
            &upper_bound,
        ):
            return best_solution_found

        vertex = _next(candidates, vertex + 1)

    return best_solution_found


cdef inline bint _can_other_vertex_open_new_part_freely(
    _Context ctx,
    int vertex,
    int level,
    uint64_t* candidates,
) noexcept:
    """If another candidate for the new part has its suffix neighbors contained in
    those of `vertex`, then `vertex` is discarded from `candidates`. Only vertices
    still in `candidates` are considered, so that a vertex that was already
    discarded can't cause another one to be discarded.
    """
    cdef uint64_t* vertex_neighbors = ctx.vertex_suffix_neighbors + level * ctx.n
    cdef uint64_t rest = candidates[0] & ~_bit(vertex)
    cdef int other_vertex
    while rest != 0:
        other_vertex = __builtin_ctzll(rest)
        rest &= rest - 1
        if _is_subset_ignoring(vertex_neighbors[other_vertex], vertex_neighbors[vertex], vertex):
            candidates[0] &= ~_bit(vertex)
            return True
    return False


cdef inline int _branch_with_vertex_on_part(
    _Context ctx,
    int vertex,
    int part,
    uint64_t suffix_vertices,
    int level,
    int parts_used,
    int lower_bound,
    int upper_bound,
) noexcept:
    """`vertex` is not in suffix."""
    ctx.prefix[level] = vertex
    ctx.part_of[vertex] = part

    cdef uint64_t previous_part_neighbors = ctx.part_neighbors[part]
    ctx.part_neighbors[part] |= ctx.graph[vertex]

    cdef int solution = _branch_and_bound(
        ctx,
        suffix_vertices,
        level + 1,
        parts_used,
        lower_bound,
        upper_bound,
    )

    ctx.part_neighbors[part] = previous_part_neighbors

    return solution


cdef inline int _increment_prefix_greedily_on_existing_parts(
    _Context ctx,
    uint64_t* suffix_vertices,
    int level,
    int parts_used,
) noexcept:
    """Add to prefix all vertices that have the same suffix neighbors as one of the parts.

    Computes the suffix neighbors at `level`, and keeps them up to date as
    vertices leave the suffix. Returns the new length of the prefix.
    """
    _compute_suffix_neighbors(ctx, suffix_vertices[0], level, parts_used)
    cdef uint64_t* vertex_neighbors = ctx.vertex_suffix_neighbors + level * ctx.n
    cdef uint64_t* part_neighbors = ctx.part_suffix_neighbors + level * ctx.max_parts
    cdef int new_level = level
    cdef uint64_t rest
    cdef int vertex
    cdef int other_vertex
    cdef int part
    cdef bint suffix_changed = True
    while suffix_changed:
        suffix_changed = False
        vertex = _next(suffix_vertices[0], 0)
        while vertex != -1:
            part = _find_greedy_part_for_vertex(vertex_neighbors[vertex], part_neighbors, parts_used, vertex)

            if part != -1:
                suffix_vertices[0] &= ~_bit(vertex)
                ctx.prefix[new_level] = vertex
                ctx.part_of[vertex] = part
                new_level += 1
                suffix_changed = True

                for part in range(parts_used):
                    part_neighbors[part] &= ~_bit(vertex)
                rest = suffix_vertices[0]
                while rest != 0:
                    other_vertex = __builtin_ctzll(rest)
                    rest &= rest - 1
                    vertex_neighbors[other_vertex] &= ~_bit(vertex)

            vertex = _next(suffix_vertices[0], vertex + 1)

    return new_level


cdef inline int _find_vertex_without_suffix_neighbors(
    _Context ctx,
    uint64_t suffix_vertices,
    int level,
) noexcept:
    """First vertex of the suffix without suffix neighbors, or -1."""
    cdef uint64_t* vertex_neighbors = ctx.vertex_suffix_neighbors + level * ctx.n
    cdef uint64_t rest = suffix_vertices
    cdef int vertex
    while rest != 0:
        vertex = __builtin_ctzll(rest)
        rest &= rest - 1
        if vertex_neighbors[vertex] == 0:
            return vertex
    return -1


cdef inline int _find_greedy_part_for_vertex(
    uint64_t vertex_neighbors,
    uint64_t* part_neighbors,
    int parts_used,
    int vertex,
) noexcept:
    """First part with the same suffix neighbors as `vertex`, ignoring `vertex` itself, or -1."""
    cdef int part
    for part in range(parts_used):
        if part_neighbors[part] & ~_bit(vertex) == vertex_neighbors:
            return part
    return -1


cdef inline bint _check_state_seen(
    _Context ctx,
    uint64_t suffix_vertices,
    int level,
    int parts_used,
) noexcept:
    """Whether a node with the same suffix and the same parts was already searched.

    Parts are compared by their suffix neighbors, which are all that matters for
    the rest of the search, and regardless of their order.
    """
    if level > ctx.max_prefix_length:
        return False
    return ctx.seen_states.contains_or_add_words(
        suffix_vertices,
        ctx.part_suffix_neighbors + level * ctx.max_parts,
        parts_used,
    )

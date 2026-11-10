"""Branch and bound for graphs of at most 64 vertices, where every set of vertices or parts is a 64-bit word.

It is the same search as the one in `branch_and_bound`, which works for graphs
of any size, function by function.
"""
from libc.stdint cimport uint64_t
from libc.string cimport memcpy
from sage.graphs.graph import Graph
from cysignals.memory cimport sig_calloc, sig_free
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
    cdef _Context ctx = _Context(graph.order(), upper_bound, max_prefix_length, max_seen_entries)
    for u, v in graph.edge_iterator(labels=False):
        ctx.graph[u] |= _bit(v)
        ctx.graph[v] |= _bit(u)
    cdef list orbit
    for orbit in graph.automorphism_group(orbits=True, return_group=False):
        ctx.canonical_vertices |= _bit(orbit[0])

    cdef int solution = _search(ctx, lower_bound, upper_bound)

    return (
        solution,
        [ctx.best_order[i] for i in range(ctx.n)],
        [ctx.best_partition[i] for i in range(ctx.n)],
    )


cdef int search_words(
    const uint64_t* graph,
    int n,
    uint64_t canonical_vertices,
    int lower_bound,
    int upper_bound,
    int max_prefix_length,
    int max_seen_entries,
    int* best_order,
) except -2:
    """Same as `search`, for a graph given by the neighbors of each vertex.

    `canonical_vertices` has one vertex of each orbit of the automorphism group.
    The order of the solution found is written to `best_order`.
    """
    cdef _Context ctx = _Context(n, upper_bound, max_prefix_length, max_seen_entries)
    memcpy(ctx.graph, graph, n * sizeof(uint64_t))
    ctx.canonical_vertices = canonical_vertices
    cdef int solution = _search(ctx, lower_bound, upper_bound)
    if solution != -1:
        memcpy(best_order, ctx.best_order, n * sizeof(int))
    return solution


cdef int _search(_Context ctx, int lower_bound, int upper_bound) except -2:
    sig_on()
    cdef int solution = _branch_and_bound(
        ctx,
        suffix_vertices=ctx.all_vertices,
        level=0,
        parts_used=0,
        lower_bound=lower_bound,
        upper_bound=upper_bound,
    )
    sig_off()
    return solution


cdef class _Context:
    """State shared by every call of the branch and bound recursion.

    The arrays with one row per prefix length (`*_suffix_neighbors` and
    `part_forbidden_vertices`) let each node of the search keep its own rows while
    its children run.
    """
    cdef int n
    cdef int max_parts
    cdef uint64_t all_vertices
    cdef uint64_t* graph
    cdef int* prefix
    cdef int* part_of
    cdef uint64_t* part_neighbors
    cdef uint64_t* forbidden_parts_for_vertices
    cdef uint64_t* vertex_suffix_neighbors
    cdef uint64_t* part_suffix_neighbors
    cdef uint64_t* part_forbidden_vertices
    cdef bint* part_forbidden_vertices_computed
    cdef uint64_t* part_states
    cdef uint64_t canonical_vertices
    cdef SeenStates seen_states
    cdef int* best_order
    cdef int* best_partition
    cdef int max_prefix_length

    def __cinit__(
        self,
        int n,
        int max_parts,
        int max_prefix_length,
        int max_seen_entries,
    ):
        """The graph and the canonical vertices are filled in afterwards."""
        if n > MAX_VERTICES or max_parts > MAX_VERTICES:
            raise ValueError(f'Graphs must have at most {MAX_VERTICES} vertices')
        self.n = n
        self.max_parts = max_parts
        self.all_vertices = _lower_bits(n)

        self.graph = <uint64_t*>sig_calloc(n, sizeof(uint64_t))
        self.prefix = <int*>sig_calloc(n, sizeof(int))
        self.part_of = <int*>sig_calloc(n, sizeof(int))
        # At least one, so that they are not NULL when there are no parts.
        self.part_neighbors = <uint64_t*>sig_calloc(max_parts + 1, sizeof(uint64_t))
        self.forbidden_parts_for_vertices = <uint64_t*>sig_calloc(n, sizeof(uint64_t))
        # One more level, as the greedy step of a node starts with them.
        self.vertex_suffix_neighbors = <uint64_t*>sig_calloc((n + 1) * n, sizeof(uint64_t))
        self.part_suffix_neighbors = <uint64_t*>sig_calloc((n + 1) * max_parts + 1, sizeof(uint64_t))
        self.part_forbidden_vertices = <uint64_t*>sig_calloc((n + 1) * max_parts + 1, sizeof(uint64_t))
        self.part_forbidden_vertices_computed = <bint*>sig_calloc(n + 1, sizeof(bint))
        self.part_states = <uint64_t*>sig_calloc(2 * max_parts + 1, sizeof(uint64_t))
        self.best_order = <int*>sig_calloc(n, sizeof(int))
        self.best_partition = <int*>sig_calloc(n, sizeof(int))
        if (
            self.graph == NULL or self.prefix == NULL or self.part_of == NULL
            or self.part_neighbors == NULL or self.forbidden_parts_for_vertices == NULL
            or self.vertex_suffix_neighbors == NULL or self.part_suffix_neighbors == NULL
            or self.part_forbidden_vertices == NULL or self.part_forbidden_vertices_computed == NULL
            or self.part_states == NULL or self.best_order == NULL or self.best_partition == NULL
        ):
            raise MemoryError

        self.seen_states = SeenStates(1, max_parts, max_seen_entries, sets_per_part=2)
        self.canonical_vertices = 0
        self.max_prefix_length = max_prefix_length

    def __dealloc__(self):
        sig_free(self.graph)
        sig_free(self.prefix)
        sig_free(self.part_of)
        sig_free(self.part_neighbors)
        sig_free(self.forbidden_parts_for_vertices)
        sig_free(self.vertex_suffix_neighbors)
        sig_free(self.part_suffix_neighbors)
        sig_free(self.part_forbidden_vertices)
        sig_free(self.part_forbidden_vertices_computed)
        sig_free(self.part_states)
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
    """Whether `subset` is a subset of `superset`, ignoring `vertex`."""
    return subset & ~_bit(vertex) & ~superset == 0


cdef inline bint _is_equal_ignoring(uint64_t first, uint64_t second, int vertex) noexcept:
    """Whether `first` and `second` are equal, ignoring `vertex`."""
    return (first ^ second) & ~_bit(vertex) == 0


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
    if suffix_vertices == 0 and parts_used <= upper_bound:
        _store_best_solution(ctx)
        return parts_used

    # Checked before the greedy step too, which is the same for the same state, so
    # that nodes already searched don't pay for it.
    if _check_state_seen(ctx, suffix_vertices, level, parts_used):
        return -1

    # The suffix neighbors of this node are kept up to date at the level it started
    # at, which no ancestor uses, as they all keep theirs at shorter prefixes.
    cdef int entry_level = level
    level = _increment_prefix_greedily_on_existing_parts(ctx, &suffix_vertices, level, parts_used)

    if level != entry_level:
        if suffix_vertices == 0 and parts_used <= upper_bound:
            _store_best_solution(ctx)
            return parts_used

        if _check_state_seen(ctx, suffix_vertices, level, parts_used):
            return -1

    cdef int best_solution_found = -1
    if _update_best_solution(
        _branch_adding_to_existing_part(
            ctx,
            suffix_vertices,
            level,
            entry_level,
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

        vertex = _find_free_vertex_for_new_part(ctx, part, suffix_vertices, entry_level)
        if vertex != -1:
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


cdef inline void _store_best_solution(_Context ctx) noexcept:
    cdef int i
    for i in range(ctx.n):
        ctx.best_order[i] = ctx.prefix[i]
        ctx.best_partition[i] = ctx.part_of[i]


cdef inline int _branch_adding_to_existing_part(
    _Context ctx,
    uint64_t suffix_vertices,
    int level,
    int neighbors_level,
    int parts_used,
    int lower_bound,
    int upper_bound,
) noexcept:
    cdef int best_solution_found = -1
    cdef uint64_t other_vertices
    cdef uint64_t parts_for_vertex
    cdef int part
    cdef int vertex = _next(suffix_vertices, 0)
    while vertex != -1:
        other_vertices = suffix_vertices & ~_bit(vertex)

        parts_for_vertex = _get_available_parts_for_vertex(
            ctx,
            vertex,
            neighbors_level,
            parts_used,
            other_vertices,
        )
        part = _next(parts_for_vertex, 0)
        while part != -1:
            if _update_best_solution(
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
            part = _next(parts_for_vertex, part + 1)

        vertex = _next(suffix_vertices, vertex + 1)

    return best_solution_found


cdef inline uint64_t _get_available_parts_for_vertex(
    _Context ctx,
    int vertex,
    int neighbors_level,
    int parts_used,
    uint64_t suffix_vertices,
) noexcept:
    """Parts that `vertex` can be added to if it is the next vertex of the prefix.

    `vertex` is not in suffix. The suffix neighbors and forbidden vertices are the
    ones stored at `neighbors_level`, which are those of the suffix with `vertex`,
    so `vertex` is ignored when comparing them. Of the parts that dominate each
    other, only one is kept, see `_is_part_dominated`.
    """
    cdef uint64_t vertex_neighbors = ctx.vertex_suffix_neighbors[neighbors_level * ctx.n + vertex]
    cdef uint64_t* part_neighbors = ctx.part_suffix_neighbors + neighbors_level * ctx.max_parts
    cdef uint64_t parts_for_vertex = 0
    cdef int part
    cdef int other_part
    for part in range(parts_used):
        if _is_subset_ignoring(part_neighbors[part], vertex_neighbors, vertex):
            parts_for_vertex |= _bit(part)
    parts_for_vertex &= ~ctx.forbidden_parts_for_vertices[vertex]

    cdef bint newly_forbidden_vertices_computed = False
    cdef uint64_t newly_forbidden_vertices = 0
    part = _next(parts_for_vertex, 0)
    while part != -1:
        other_part = _next(parts_for_vertex, 0)
        while other_part != -1 and other_part < part:
            if _is_part_dominated(
                ctx, vertex, neighbors_level, parts_used, part, other_part, suffix_vertices,
                &newly_forbidden_vertices_computed, &newly_forbidden_vertices,
            ):
                parts_for_vertex &= ~_bit(part)
                break
            elif _is_part_dominated(
                ctx, vertex, neighbors_level, parts_used, other_part, part, suffix_vertices,
                &newly_forbidden_vertices_computed, &newly_forbidden_vertices,
            ):
                parts_for_vertex &= ~_bit(other_part)
            other_part = _next(parts_for_vertex, other_part + 1)
        part = _next(parts_for_vertex, part + 1)

    return parts_for_vertex


cdef inline bint _is_part_dominated(
    _Context ctx,
    int vertex,
    int neighbors_level,
    int parts_used,
    int part,
    int other_part,
    uint64_t suffix_vertices,
    bint* newly_forbidden_vertices_computed,
    uint64_t* newly_forbidden_vertices,
) noexcept:
    """Whether adding `vertex` to `other_part` is always at least as good as adding it to `part`.

    See `branch_and_bound._is_part_dominated`. The newly forbidden vertices of
    `vertex` are computed the first time they are needed, in
    `newly_forbidden_vertices`.
    """
    cdef uint64_t* part_neighbors = ctx.part_suffix_neighbors + neighbors_level * ctx.max_parts
    cdef uint64_t* part_forbidden_vertices = ctx.part_forbidden_vertices + neighbors_level * ctx.max_parts
    if not _is_subset_ignoring(part_neighbors[part], part_neighbors[other_part], vertex):
        return False
    if not ctx.part_forbidden_vertices_computed[neighbors_level]:
        _compute_part_forbidden_vertices(ctx, neighbors_level, suffix_vertices | _bit(vertex), parts_used)
    if not _is_subset_ignoring(part_forbidden_vertices[part], part_forbidden_vertices[other_part], vertex):
        return False
    if not newly_forbidden_vertices_computed[0]:
        newly_forbidden_vertices[0] = _newly_forbidden_vertices(ctx, vertex, suffix_vertices)
        newly_forbidden_vertices_computed[0] = True
    return _is_subset_ignoring(
        part_forbidden_vertices[other_part],
        part_forbidden_vertices[part] | newly_forbidden_vertices[0],
        vertex,
    )


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
    cdef uint64_t candidates = ctx.canonical_vertices if level == 0 else suffix_vertices
    cdef int vertex = _next(candidates, 0)
    while vertex != -1:
        if _update_best_solution(
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

    # Forbid the part for the suffix vertices that can't go after `vertex` in it,
    # remembering those that didn't have it forbidden yet to undo it.
    cdef uint64_t part_bit = _bit(part)
    cdef uint64_t vertices_forbidden = 0
    cdef uint64_t rest = _newly_forbidden_vertices(ctx, vertex, suffix_vertices)
    cdef int forbidden_vertex
    while rest != 0:
        forbidden_vertex = __builtin_ctzll(rest)
        rest &= rest - 1
        if not ctx.forbidden_parts_for_vertices[forbidden_vertex] & part_bit:
            ctx.forbidden_parts_for_vertices[forbidden_vertex] |= part_bit
            vertices_forbidden |= _bit(forbidden_vertex)

    cdef int solution = _branch_and_bound(
        ctx,
        suffix_vertices,
        level + 1,
        parts_used,
        lower_bound,
        upper_bound,
    )

    ctx.part_neighbors[part] = previous_part_neighbors
    while vertices_forbidden != 0:
        forbidden_vertex = __builtin_ctzll(vertices_forbidden)
        vertices_forbidden &= vertices_forbidden - 1
        ctx.forbidden_parts_for_vertices[forbidden_vertex] &= ~part_bit

    return solution


cdef inline int _increment_prefix_greedily_on_existing_parts(
    _Context ctx,
    uint64_t* suffix_vertices,
    int level,
    int parts_used,
) noexcept:
    """Add to prefix all vertices that can be added to an existing part for free.

    Computes the suffix neighbors of the vertices and the parts at `level`, and
    keeps them up to date as vertices leave the suffix. Returns the new length of
    the prefix.
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
            part = _find_free_part_for_vertex(ctx, vertex, level, suffix_vertices[0] & ~_bit(vertex), parts_used)

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


cdef inline void _compute_suffix_neighbors(
    _Context ctx,
    uint64_t suffix_vertices,
    int level,
    int parts_used,
) noexcept:
    """Suffix neighbors of the parts and of the suffix vertices, stored at `level`.

    The suffix vertices forbidden from each part are only computed when they are
    needed, by `_compute_part_forbidden_vertices`.
    """
    ctx.part_forbidden_vertices_computed[level] = False
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


cdef inline void _compute_part_forbidden_vertices(
    _Context ctx,
    int level,
    uint64_t suffix_vertices,
    int parts_used,
) noexcept:
    """Suffix vertices forbidden from each part, stored at `level`."""
    cdef uint64_t* part_forbidden_vertices = ctx.part_forbidden_vertices + level * ctx.max_parts
    cdef int part
    for part in range(parts_used):
        part_forbidden_vertices[part] = 0
    cdef uint64_t rest = suffix_vertices
    cdef uint64_t parts
    cdef int vertex
    while rest != 0:
        vertex = __builtin_ctzll(rest)
        rest &= rest - 1
        parts = ctx.forbidden_parts_for_vertices[vertex]
        while parts != 0:
            part_forbidden_vertices[__builtin_ctzll(parts)] |= _bit(vertex)
            parts &= parts - 1
    ctx.part_forbidden_vertices_computed[level] = True


cdef inline int _find_free_vertex_for_new_part(
    _Context ctx,
    int part,
    uint64_t suffix_vertices,
    int neighbors_level,
) noexcept:
    """A vertex that can be added to the new, empty `part` for free, or -1.

    As the part has no suffix neighbors, the vertex can't have any either. The
    suffix neighbors of the vertices are the ones stored at `neighbors_level`.
    """
    cdef uint64_t* vertex_neighbors = ctx.vertex_suffix_neighbors + neighbors_level * ctx.n
    cdef uint64_t rest = suffix_vertices
    cdef int vertex
    while rest != 0:
        vertex = __builtin_ctzll(rest)
        rest &= rest - 1
        if (
            vertex_neighbors[vertex] == 0
            and not ctx.forbidden_parts_for_vertices[vertex] & _bit(part)
            and _are_forbidden_from_part(
                ctx,
                _newly_forbidden_vertices(ctx, vertex, suffix_vertices & ~_bit(vertex)),
                part,
            )
        ):
            return vertex
    return -1


cdef inline int _find_free_part_for_vertex(
    _Context ctx,
    int vertex,
    int level,
    uint64_t suffix_vertices,
    int parts_used,
) noexcept:
    """First part that `vertex` can be added to for free, or -1.

    See `branch_and_bound._find_free_part_for_vertex`. `vertex` is not in suffix.
    """
    cdef uint64_t vertex_neighbors = ctx.vertex_suffix_neighbors[level * ctx.n + vertex]
    cdef uint64_t* part_neighbors = ctx.part_suffix_neighbors + level * ctx.max_parts
    cdef bint newly_forbidden_vertices_computed = False
    cdef uint64_t newly_forbidden_vertices = 0
    cdef int part
    for part in range(parts_used):
        if ctx.forbidden_parts_for_vertices[vertex] & _bit(part):
            continue
        if not _is_equal_ignoring(part_neighbors[part], vertex_neighbors, vertex):
            continue
        if not newly_forbidden_vertices_computed:
            newly_forbidden_vertices = _newly_forbidden_vertices(ctx, vertex, suffix_vertices)
            newly_forbidden_vertices_computed = True
        if _are_forbidden_from_part(ctx, newly_forbidden_vertices, part):
            return part
    return -1


cdef inline bint _are_forbidden_from_part(_Context ctx, uint64_t vertices, int part) noexcept:
    cdef int vertex
    while vertices != 0:
        vertex = __builtin_ctzll(vertices)
        vertices &= vertices - 1
        if not ctx.forbidden_parts_for_vertices[vertex] & _bit(part):
            return False
    return True


cdef inline uint64_t _newly_forbidden_vertices(
    _Context ctx,
    int new_vertex,
    uint64_t suffix_vertices,
) noexcept:
    """Suffix vertices that can't be in the part of `new_vertex`, if it's the last vertex of the prefix.

    Those are the ones adjacent to a prefix vertex that isn't adjacent to
    `new_vertex`. `new_vertex` is not in suffix.
    """
    cdef uint64_t prefix_non_neighbors = (
        ctx.all_vertices & ~suffix_vertices & ~ctx.graph[new_vertex] & ~_bit(new_vertex)
    )
    cdef uint64_t newly_forbidden_vertices = 0
    while prefix_non_neighbors != 0:
        newly_forbidden_vertices |= ctx.graph[__builtin_ctzll(prefix_non_neighbors)]
        prefix_non_neighbors &= prefix_non_neighbors - 1
    return newly_forbidden_vertices & suffix_vertices


cdef inline bint _check_state_seen(
    _Context ctx,
    uint64_t suffix_vertices,
    int level,
    int parts_used,
) noexcept:
    """Whether a node with the same suffix and the same parts was already searched.

    All that matters of a part for the rest of the search are its suffix
    neighbors and the suffix vertices that can't be added to it. Parts are
    compared by those, regardless of their order.
    """
    if level > ctx.max_prefix_length:
        return False
    cdef int part
    for part in range(parts_used):
        ctx.part_states[2 * part] = ctx.part_neighbors[part] & suffix_vertices
        ctx.part_states[2 * part + 1] = 0
    cdef uint64_t rest = suffix_vertices
    cdef uint64_t parts
    cdef int vertex
    while rest != 0:
        vertex = __builtin_ctzll(rest)
        rest &= rest - 1
        parts = ctx.forbidden_parts_for_vertices[vertex]
        while parts != 0:
            ctx.part_states[2 * __builtin_ctzll(parts) + 1] |= _bit(vertex)
            parts &= parts - 1
    return ctx.seen_states.contains_or_add_words(suffix_vertices, ctx.part_states, parts_used)

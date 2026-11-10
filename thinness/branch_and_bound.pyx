import itertools

from sage.graphs.graph import Graph
from sage.data_structures.binary_matrix cimport *
from sage.graphs.base.static_dense_graph cimport dense_graph_init
from cysignals.memory cimport sig_malloc, sig_calloc, sig_free
from cysignals.signals cimport sig_on, sig_off
from sage.graphs.graph_decompositions.vertex_separation import vertex_separation

from thinness import branch_and_bound_64
from thinness.consistent_solution import ConsistentSolution
from thinness.optimizations import ALL_OPTIMIZATIONS, Optimization
from thinness.seen_states cimport SeenStates
from thinness.vertex_separation import solution_from_vertex_separation

DEFAULT_MAX_PREFIX_LENGTH = 15
DEFAULT_MAX_SEEN_ENTRIES = 1_000_000
# Graphs with at most this many vertices are searched with 64-bit words instead of bitsets.
MAX_VERTICES_FOR_WORDS = branch_and_bound_64.MAX_VERTICES

cdef int _SYMMETRY = Optimization.SYMMETRY
cdef int _SEEN_STATES = Optimization.SEEN_STATES
cdef int _GREEDY_EXISTING_PART = Optimization.GREEDY_EXISTING_PART
cdef int _PART_DOMINANCE = Optimization.PART_DOMINANCE
cdef int _VERTEX_DOMINANCE = Optimization.VERTEX_DOMINANCE
cdef int _NEW_PART_ONLY_IF_NEEDED = Optimization.NEW_PART_ONLY_IF_NEEDED
cdef int _NEW_PART_DOMINANCE = Optimization.NEW_PART_DOMINANCE
cdef int _UNLOCKING = Optimization.UNLOCKING


def calculate_thinness(
    graph: Graph,
    lower_bound: int = 1,
    upper_bound: int = None,
    certificate: bool = False,
    max_prefix_length: int = DEFAULT_MAX_PREFIX_LENGTH,
    max_seen_entries: int = DEFAULT_MAX_SEEN_ENTRIES,
    optimizations: Optimization = ALL_OPTIMIZATIONS,
    statistics: dict | None = None,
) -> ConsistentSolution | int:
    """`optimizations` is the combination of `Optimization` flags to use, all of them by default.

    If `statistics` is given, its `'nodes'` is set to the number of nodes the
    branch and bound searched.
    """
    if statistics is not None:
        statistics['nodes'] = 0
    if optimizations & Optimization.COMPONENTS:
        # Largest first, as they are the most likely to have the largest thinness.
        components = [
            graph.subgraph(component, immutable=False)
            for component in sorted(graph.connected_components(sort=False), key=len, reverse=True)
        ]
    else:
        components = [graph.copy(immutable=False)]
    relabellings = [component.relabel(return_map=True) for component in components]
    solutions = []
    for component in components:
        solution = calculate_thinness_of_connected_graph(
            component,
            lower_bound,
            upper_bound,
            certificate,
            max_prefix_length,
            max_seen_entries,
            optimizations,
            statistics,
        )
        solutions.append(solution)
        # The thinness of the graph is the maximum over its components, so the
        # remaining components don't need to beat this one.
        lower_bound = max(lower_bound, solution.thinness if certificate else solution)

    if certificate:
        return _join_solutions(solutions, relabellings)
    else:
        return max(solutions)


def _join_solutions(solutions: list[ConsistentSolution], relabellings: list[dict]) -> ConsistentSolution:
    original_labels = [
        {new_label: original_label for original_label, new_label in relabelling.items()}
        for relabelling in relabellings
    ]
    order = _join_orders([solution.order for solution in solutions], original_labels)
    partition = _join_partitions([solution.partition for solution in solutions], original_labels)
    return ConsistentSolution(order, partition)


def _join_orders(orders: list[list[int]], original_labels: list[dict]) -> list[int]:
    orders = [
        [original_labels[i][vertex] for vertex in order]
        for i, order in enumerate(orders)
    ]
    return list(itertools.chain.from_iterable(orders))


def _join_partitions(partitions: list[list[set]], original_labels: list[dict]) -> list[set]:
    partitions = [
        [set(original_labels[i][vertex] for vertex in part) for part in partition]
        for i, partition in enumerate(partitions)
    ]
    return [
        set(itertools.chain.from_iterable(parts))
        for parts in itertools.zip_longest(*partitions, fillvalue=set())
    ]


def calculate_thinness_of_connected_graph(
    graph: Graph,
    lower_bound: int = 1,
    upper_bound: int = None,
    certificate: bool = False,
    max_prefix_length: int = DEFAULT_MAX_PREFIX_LENGTH,
    max_seen_entries: int = DEFAULT_MAX_SEEN_ENTRIES,
    optimizations: Optimization = ALL_OPTIMIZATIONS,
    statistics: dict | None = None,
) -> ConsistentSolution | int:
    """upper_bound is exclusive.

    Without `Optimization.COMPONENTS`, the graph doesn't need to be connected. If
    `statistics` is given, the nodes searched are added to its `'nodes'`.
    """
    if optimizations & Optimization.VERTEX_SEPARATION_BOUND:
        vertex_separation_value, vertex_separation_order = vertex_separation(graph)
        initial_upper_bound = max(vertex_separation_value, 1)
    else:
        # Every vertex on its own part is a solution.
        initial_upper_bound = max(graph.order(), 1)
        vertex_separation_order = None
    if initial_upper_bound <= lower_bound:
        if certificate:
            return _fallback_solution(graph, vertex_separation_order)
        else:
            return initial_upper_bound
    upper_bound = (
        initial_upper_bound
        if upper_bound is None
        else min(upper_bound, initial_upper_bound)
    )

    search = (
        branch_and_bound_64.search
        if graph.order() <= MAX_VERTICES_FOR_WORDS
        else _search_with_bitsets
    )
    branch_and_bound_thinness, best_order, best_partition, nodes = search(
        graph,
        lower_bound,
        upper_bound - 1,
        max_prefix_length,
        max_seen_entries,
        optimizations,
    )
    if statistics is not None:
        statistics['nodes'] = statistics.get('nodes', 0) + nodes

    cdef int thinness = branch_and_bound_thinness if branch_and_bound_thinness != -1 else upper_bound
    cdef list partition
    if certificate:
        if branch_and_bound_thinness == -1:
            return _fallback_solution(graph, vertex_separation_order)
        partition = [set() for _ in range(thinness)]
        for vertex, part in enumerate(best_partition):
            partition[part].add(vertex)
        return ConsistentSolution(best_order, partition)
    else:
        return thinness


def _fallback_solution(graph: Graph, vertex_separation_order: list | None) -> ConsistentSolution:
    """The solution given by the vertex separation, or, without it, the one with every vertex on its own part."""
    if vertex_separation_order is None:
        return ConsistentSolution(list(graph), [{vertex} for vertex in graph])
    return solution_from_vertex_separation(graph, vertex_separation_order)


def _search_with_bitsets(
    graph: Graph,
    int lower_bound,
    int upper_bound,
    int max_prefix_length,
    int max_seen_entries,
    int optimizations=ALL_OPTIMIZATIONS,
) -> tuple[int, list[int], list[int], int]:
    """Same as `branch_and_bound_64.search`, for graphs of any size."""
    cdef _Context ctx = _Context(graph, upper_bound, max_prefix_length, max_seen_entries, optimizations)

    sig_on()
    cdef int solution = _branch_and_bound(
        ctx,
        suffix_vertices=ctx.all_vertices,
        level=0,
        parts_used=0,
        lower_bound=lower_bound,
        upper_bound=upper_bound,
        last_vertex=-1,
    )
    sig_off()

    return (
        solution,
        [ctx.best_order[i] for i in range(ctx.n)],
        [ctx.best_partition[i] for i in range(ctx.n)],
        ctx.nodes,
    )


cdef class _Context:
    """State shared by every call of the branch and bound recursion.

    Holds the graph, the scratch buffers and the search settings, so that the
    recursive functions only receive the values that change between calls.

    The arrays of matrices have one matrix per prefix length, so that each
    node of the search keeps its own while its children run.
    """
    cdef int n
    cdef binary_matrix_t graph
    cdef int* prefix
    cdef int* part_of
    cdef bitset_t all_vertices
    cdef binary_matrix_t new_suffixes
    cdef binary_matrix_t part_neighbors
    cdef binary_matrix_t previous_part_neighbors
    cdef binary_matrix_t* vertex_suffix_neighbors
    cdef binary_matrix_t* part_suffix_neighbors
    cdef binary_matrix_t* parts_for_vertices
    cdef bitset_t unlocked_vertices
    cdef binary_matrix_t vertices_not_added
    cdef binary_matrix_t other_new_part_candidates
    cdef binary_matrix_t unlockers
    cdef bitset_t ignored_vertices
    cdef bitset_t greedy_changed_vertices
    cdef bitset_t greedy_changed_parts
    cdef bitset_t greedy_candidates
    cdef SeenStates seen_states
    cdef bitset_t canonical_vertices
    cdef int* best_order
    cdef int* best_partition
    cdef int max_prefix_length
    cdef int max_seen_entries
    cdef int optimizations
    cdef long long nodes

    def __cinit__(
        self,
        graph: Graph,
        int max_parts,
        int max_prefix_length,
        int max_seen_entries,
        int optimizations,
    ):
        dense_graph_init(self.graph, graph)

        cdef int n = self.graph.n_cols
        self.n = n

        self.prefix = <int*>sig_malloc(sizeof(int) * n)
        self.part_of = <int*>sig_malloc(sizeof(int) * n)

        bitset_init(self.all_vertices, n)
        bitset_complement(self.all_vertices, self.all_vertices)

        binary_matrix_init(self.new_suffixes, n+1, n)
        binary_matrix_init(self.part_neighbors, max_parts, n)
        binary_matrix_init(self.previous_part_neighbors, n, n)

        # Zeroed so that __dealloc__ can free them even if an init below fails.
        # One more level for the suffix neighbors, as the greedy step of a node starts with them.
        self.vertex_suffix_neighbors = <binary_matrix_t*>sig_calloc(n + 1, sizeof(binary_matrix_t))
        self.part_suffix_neighbors = <binary_matrix_t*>sig_calloc(n + 1, sizeof(binary_matrix_t))
        self.parts_for_vertices = <binary_matrix_t*>sig_calloc(n, sizeof(binary_matrix_t))
        _init_matrices(self.vertex_suffix_neighbors, n + 1, n, n)
        _init_matrices(self.part_suffix_neighbors, n + 1, max_parts, n)
        _init_matrices(self.parts_for_vertices, n, n, max_parts)

        bitset_init(self.unlocked_vertices, n)
        binary_matrix_init(self.vertices_not_added, n, n)
        binary_matrix_init(self.other_new_part_candidates, n, n)
        binary_matrix_init(self.unlockers, n, n)
        bitset_init(self.ignored_vertices, n)
        # Scratch sets of the greedy step, which never runs while another one does.
        bitset_init(self.greedy_changed_vertices, n)
        bitset_init(self.greedy_changed_parts, max(max_parts, 1))
        bitset_init(self.greedy_candidates, n)

        self.seen_states = SeenStates(self.all_vertices.limbs, max_parts, max_seen_entries)

        bitset_init(self.canonical_vertices, n)
        if optimizations & _SYMMETRY:
            _build_canonical_vertices(graph, self.canonical_vertices)
        else:
            bitset_copy(self.canonical_vertices, self.all_vertices)

        self.best_order = <int*>sig_malloc(sizeof(int) * n)
        self.best_partition = <int*>sig_malloc(sizeof(int) * n)

        self.max_prefix_length = max_prefix_length
        self.max_seen_entries = max_seen_entries
        self.optimizations = optimizations
        self.nodes = 0

    def __dealloc__(self):
        binary_matrix_free(self.graph)
        sig_free(self.prefix)
        sig_free(self.part_of)
        bitset_free(self.all_vertices)
        binary_matrix_free(self.new_suffixes)
        binary_matrix_free(self.part_neighbors)
        binary_matrix_free(self.previous_part_neighbors)
        _free_matrices(self.vertex_suffix_neighbors, self.n + 1)
        _free_matrices(self.part_suffix_neighbors, self.n + 1)
        _free_matrices(self.parts_for_vertices, self.n)
        bitset_free(self.unlocked_vertices)
        binary_matrix_free(self.vertices_not_added)
        binary_matrix_free(self.other_new_part_candidates)
        binary_matrix_free(self.unlockers)
        bitset_free(self.ignored_vertices)
        bitset_free(self.greedy_changed_vertices)
        bitset_free(self.greedy_changed_parts)
        bitset_free(self.greedy_candidates)
        bitset_free(self.canonical_vertices)
        sig_free(self.best_order)
        sig_free(self.best_partition)


cdef inline int _init_matrices(binary_matrix_t* matrices, int count, int n_rows, int n_cols) except -1:
    cdef int i
    if matrices == NULL:
        raise MemoryError
    for i in range(count):
        binary_matrix_init(matrices[i], n_rows, n_cols)


cdef inline void _free_matrices(binary_matrix_t* matrices, int count) noexcept:
    cdef int i
    if matrices != NULL:
        for i in range(count):
            binary_matrix_free(matrices[i])
        sig_free(matrices)


cdef inline void _build_canonical_vertices(graph: Graph, bitset_t canonical_vertices):
    cdef list orbit
    for orbit in graph.automorphism_group(orbits=True, return_group=False):
        bitset_add(canonical_vertices, <int> orbit[0])


cdef int _branch_and_bound(
    _Context ctx,
    bitset_t suffix_vertices,
    int level,
    int parts_used,
    int lower_bound,
    int upper_bound,
    int last_vertex,
) noexcept:
    """Search for a solution that extends the current prefix.

    `level` is the length of the prefix. Both bounds are inclusive: only
    solutions with at most `upper_bound` parts are searched for, and the search
    stops as soon as one with at most `lower_bound` parts is found. Returns the
    number of parts of the best solution found, which is stored in
    `ctx.best_order` and `ctx.best_partition`, or -1 if none was found.
    `last_vertex` is the last vertex of the prefix, or -1 if it is empty.
    """
    ctx.nodes += 1
    cdef bitset_t new_suffix = ctx.new_suffixes.rows[level]
    bitset_copy(new_suffix, suffix_vertices)

    cdef int entry_level = level
    level = _increment_prefix_greedily_on_existing_parts(ctx, new_suffix, level, parts_used, last_vertex)

    if bitset_isempty(new_suffix) and parts_used <= upper_bound:
        _copy_array(ctx.n, ctx.prefix, ctx.best_order)
        _copy_array(ctx.n, ctx.part_of, ctx.best_partition)
        return parts_used

    # The greedy step left the suffix neighbors at the level the node started at,
    # which no ancestor uses, as they all keep theirs at shorter prefixes.
    if level != entry_level:
        _compute_suffix_neighbors(ctx, new_suffix, level, parts_used)

    if _check_state_seen(ctx, new_suffix, level, parts_used):
        return -1

    cdef int best_solution_found = -1
    if _update_best_solution(
        _branch_adding_to_existing_part(
            ctx,
            new_suffix,
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
    if parts_used < upper_bound:
        parts_used += 1
        lower_bound = max(lower_bound, parts_used)
        new_part_solution = _branch_adding_to_new_part(
            ctx,
            new_suffix,
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
    bitset_t suffix_vertices,
    int level,
    int parts_used,
) noexcept:
    """Suffix neighbors of the parts and of the suffix vertices, stored at `level`."""
    cdef int part
    for part in range(parts_used):
        bitset_intersection(
            ctx.part_suffix_neighbors[level].rows[part],
            ctx.part_neighbors.rows[part],
            suffix_vertices
        )
    cdef int vertex = bitset_next(suffix_vertices, 0)
    while vertex != -1:
        bitset_intersection(
            ctx.vertex_suffix_neighbors[level].rows[vertex],
            ctx.graph.rows[vertex],
            suffix_vertices
        )
        vertex = bitset_next(suffix_vertices, vertex + 1)


cdef inline bint _is_subset_ignoring(bitset_t subset, bitset_t superset, int vertex) noexcept:
    """Whether `subset` is a subset of `superset`, ignoring `vertex`.

    The suffix neighbors computed at a node include the vertex that is about to
    be added to the prefix, which has to be ignored when comparing them.
    """
    if bitset_in(superset, vertex) or not bitset_in(subset, vertex):
        return bitset_issubset(subset, superset)
    bitset_discard(subset, vertex)
    cdef bint is_subset = bitset_issubset(subset, superset)
    bitset_add(subset, vertex)
    return is_subset


cdef inline bint _is_equal_ignoring(bitset_t first, bitset_t second, int vertex) noexcept:
    """Whether `first` and `second` are equal, ignoring `vertex`."""
    if bitset_in(first, vertex) == bitset_in(second, vertex):
        return bitset_eq(first, second)
    bitset_flip(first, vertex)
    cdef bint is_equal = bitset_eq(first, second)
    bitset_flip(first, vertex)
    return is_equal


cdef inline int _branch_adding_to_existing_part(
    _Context ctx,
    bitset_t suffix_vertices,
    int level,
    int parts_used,
    int lower_bound,
    int upper_bound,
) noexcept:
    cdef bitset_t my_vertices_not_added = ctx.vertices_not_added.rows[level]
    bitset_clear(my_vertices_not_added)
    cdef int best_solution_found = -1
    cdef bitset_s* parts_for_vertex
    cdef int part
    cdef int vertex

    vertex = bitset_next(suffix_vertices, 0)
    while vertex != -1:
        bitset_clear(ctx.unlockers.rows[vertex])
        vertex = bitset_next(suffix_vertices, vertex + 1)

    vertex = bitset_next(suffix_vertices, 0)
    while vertex != -1:
        parts_for_vertex = ctx.parts_for_vertices[level].rows[vertex]
        _get_available_parts_for_vertex(ctx, vertex, level, parts_used, parts_for_vertex)
        if bitset_isempty(parts_for_vertex):
            bitset_add(my_vertices_not_added, vertex)
        vertex = bitset_next(suffix_vertices, vertex + 1)

    # Without NEW_PART_ONLY_IF_NEEDED, the vertices that can be added to an existing
    # part also start a new one. They are kept apart, as NEW_PART_DOMINANCE only
    # compares the ones that can't.
    cdef bitset_t other_candidates = ctx.other_new_part_candidates.rows[level]
    if ctx.optimizations & _NEW_PART_ONLY_IF_NEEDED:
        bitset_clear(other_candidates)
    else:
        bitset_difference(other_candidates, suffix_vertices, my_vertices_not_added)

    if ctx.optimizations & _UNLOCKING:
        _ignore_unlocked_vertices(ctx, level, suffix_vertices, my_vertices_not_added)
        bitset_difference(other_candidates, other_candidates, ctx.ignored_vertices)

    vertex = bitset_next(suffix_vertices, 0)
    while vertex != -1:
        bitset_discard(suffix_vertices, vertex)

        parts_for_vertex = ctx.parts_for_vertices[level].rows[vertex]
        part = bitset_next(parts_for_vertex, 0)
        while part != -1:
            if not (ctx.optimizations & _VERTEX_DOMINANCE and _can_other_vertex_be_prepended_freely(
                ctx,
                vertex,
                part,
                level,
                suffix_vertices,
            )) and _update_best_solution(
                _branch_with_vertex_on_part(
                    ctx,
                    vertex,
                    part,
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
            part = bitset_next(parts_for_vertex, part + 1)

        bitset_add(suffix_vertices, vertex)
        vertex = bitset_next(suffix_vertices, vertex + 1)

    return best_solution_found


cdef inline void _get_available_parts_for_vertex(
    _Context ctx,
    int vertex,
    int level,
    int parts_used,
    bitset_s* parts_for_vertex,
) noexcept:
    """Parts that `vertex` can be added to if it is the next vertex of the prefix.

    Also records in `ctx.unlockers` the vertices that `vertex` unlocks, see
    `_ignore_unlocked_vertices`.
    """
    cdef bitset_s* vertex_neighbors = ctx.vertex_suffix_neighbors[level].rows[vertex]
    cdef bitset_t* part_neighbors = ctx.part_suffix_neighbors[level].rows
    cdef long suffix_degree = bitset_len(vertex_neighbors)
    cdef long unlocked_vertex
    cdef int part
    cdef int other_part

    bitset_clear(parts_for_vertex)
    for part in range(parts_used):
        if _is_subset_ignoring(part_neighbors[part], vertex_neighbors, vertex):
            bitset_add(parts_for_vertex, part)
            if (
                bitset_len(part_neighbors[part]) - bitset_in(part_neighbors[part], vertex)
                == suffix_degree - 1
            ):
                bitset_difference(ctx.unlocked_vertices, vertex_neighbors, part_neighbors[part])
                unlocked_vertex = bitset_first(ctx.unlocked_vertices)
                bitset_add(ctx.unlockers.rows[unlocked_vertex], vertex)

    if not ctx.optimizations & _PART_DOMINANCE:
        return

    for part in range(parts_used):
        if bitset_in(parts_for_vertex, part):
            for other_part in range(part):
                if bitset_in(parts_for_vertex, other_part):
                    if _is_subset_ignoring(part_neighbors[part], part_neighbors[other_part], vertex):
                        bitset_discard(parts_for_vertex, part)
                        break
                    elif _is_subset_ignoring(part_neighbors[other_part], part_neighbors[part], vertex):
                        bitset_discard(parts_for_vertex, other_part)


cdef inline int _can_other_vertex_be_prepended_freely(
    _Context ctx,
    int vertex,
    int part,
    int level,
    bitset_t suffix_vertices,
) noexcept:
    """`vertex` is not in suffix."""
    cdef bitset_t* vertex_neighbors = ctx.vertex_suffix_neighbors[level].rows
    cdef bitset_t* parts_for_vertices = ctx.parts_for_vertices[level].rows
    cdef int other_vertex = bitset_next(suffix_vertices, 0)
    while other_vertex != -1:
        if bitset_in(parts_for_vertices[other_vertex], part) and _is_subset_ignoring(
            vertex_neighbors[other_vertex],
            vertex_neighbors[vertex],
            vertex,
        ):
            bitset_discard(parts_for_vertices[vertex], part)
            return True
        other_vertex = bitset_next(suffix_vertices, other_vertex + 1)
    return False


cdef inline void _ignore_unlocked_vertices(
    _Context ctx,
    int level,
    bitset_t suffix_vertices,
    bitset_t vertices_not_added,
) noexcept:
    """Remove from this level's candidates the vertices that some other vertex unlocks.

    A vertex `u` unlocks `v` if `u` can be added to some part so that the part's
    suffix neighbors only gain `v`. In that case putting `u` and then `v` is
    always preferable to putting `v` next, so `v` is not branched on, neither on
    an existing part nor on a new one.

    Vertices already ignored don't unlock others, so that two vertices can't
    cause each other to be ignored.
    """
    bitset_clear(ctx.ignored_vertices)
    cdef int vertex = bitset_next(suffix_vertices, 0)
    while vertex != -1:
        if not bitset_issubset(ctx.unlockers.rows[vertex], ctx.ignored_vertices):
            bitset_add(ctx.ignored_vertices, vertex)
            bitset_clear(ctx.parts_for_vertices[level].rows[vertex])
            bitset_discard(vertices_not_added, vertex)
        vertex = bitset_next(suffix_vertices, vertex + 1)


cdef inline int _branch_adding_to_new_part(
    _Context ctx,
    bitset_t suffix_vertices,
    int level,
    int parts_used,
    int lower_bound,
    int upper_bound,
) noexcept:
    cdef int best_solution_found = -1
    cdef int part = parts_used - 1
    # Vertices discarded by _can_other_vertex_open_new_part_freely are removed from here.
    cdef bitset_t candidates = ctx.vertices_not_added.rows[level]
    cdef bitset_t other_candidates = ctx.other_new_part_candidates.rows[level]
    if level == 0:
        bitset_copy(candidates, ctx.canonical_vertices)
    cdef long vertex = _next_in_union(candidates, other_candidates, 0)
    while vertex != -1:
        bitset_discard(suffix_vertices, vertex)

        if not (
            bitset_in(candidates, vertex)
            and ctx.optimizations & _NEW_PART_DOMINANCE
            and _can_other_vertex_open_new_part_freely(ctx, vertex, level, candidates)
        ) and _update_best_solution(
            _branch_with_vertex_on_part(
                ctx,
                vertex,
                part,
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

        bitset_add(suffix_vertices, vertex)
        vertex = _next_in_union(candidates, other_candidates, vertex + 1)

    return best_solution_found


cdef inline long _next_in_union(bitset_t first, bitset_t second, long start) noexcept:
    """The smallest element of either set that is at least `start`, or -1."""
    cdef long first_next = bitset_next(first, start)
    cdef long second_next = bitset_next(second, start)
    if first_next == -1:
        return second_next
    if second_next == -1:
        return first_next
    return min(first_next, second_next)


cdef inline bint _can_other_vertex_open_new_part_freely(
    _Context ctx,
    int vertex,
    int level,
    bitset_t candidates,
) noexcept:
    """If another candidate for the new part has its suffix neighbors contained in
    those of `vertex`, then `vertex` is discarded from `candidates`. Only vertices
    still in `candidates` are considered, so that a vertex that was already
    discarded can't cause another one to be discarded.
    """
    cdef bitset_t* vertex_neighbors = ctx.vertex_suffix_neighbors[level].rows
    cdef int other_vertex = bitset_next(candidates, 0)
    while other_vertex != -1:
        if other_vertex != vertex and _is_subset_ignoring(
            vertex_neighbors[other_vertex],
            vertex_neighbors[vertex],
            vertex,
        ):
            bitset_discard(candidates, vertex)
            return True
        other_vertex = bitset_next(candidates, other_vertex + 1)
    return False


cdef inline int _branch_with_vertex_on_part(
    _Context ctx,
    int vertex,
    int part,
    bitset_t suffix_vertices,
    int level,
    int parts_used,
    int lower_bound,
    int upper_bound,
) noexcept:
    """`vertex` is not in suffix."""
    ctx.prefix[level] = vertex
    ctx.part_of[vertex] = part

    _update_part_neighbors(
        ctx.part_neighbors.rows[part],
        ctx.previous_part_neighbors.rows[vertex],
        ctx.graph.rows[vertex]
    )

    cdef int solution = _branch_and_bound(
        ctx,
        suffix_vertices,
        level + 1,
        parts_used,
        lower_bound,
        upper_bound,
        vertex,
    )

    _undo_update_part_neighbors(
        ctx.part_neighbors.rows[part],
        ctx.previous_part_neighbors.rows[vertex]
    )

    return solution


cdef inline int _increment_prefix_greedily_on_existing_parts(
    _Context ctx,
    bitset_t suffix_vertices,
    int level,
    int parts_used,
    int last_vertex,
) noexcept:
    """Add to prefix all vertices that have the same suffix neighbors as one of the parts.

    Computes the suffix neighbors at `level`, and keeps them up to date as
    vertices leave the suffix. Returns the new length of the prefix.

    The parent node already added every such vertex, so a vertex can only have
    the same suffix neighbors as a part now if those of one of them changed
    when `last_vertex` was added to the prefix. Those are the vertices adjacent
    to `last_vertex`, its part, and the parts that had it as a suffix neighbor.
    Each vertex added here changes them in the same way, so they are checked
    until none is left. The part a vertex is added to is checked again too, as
    another vertex may have the same suffix neighbors as it. `last_vertex` is -1
    at the root, which has no parts.

    A vertex that can be added stays so when others are added, as both its
    suffix neighbors and those of the part lose the same vertices, so the
    vertices added don't depend on the order in which they are checked.
    """
    _compute_suffix_neighbors(ctx, suffix_vertices, level, parts_used)
    if not ctx.optimizations & _GREEDY_EXISTING_PART or last_vertex == -1:
        return level
    cdef bitset_t* vertex_neighbors = ctx.vertex_suffix_neighbors[level].rows
    cdef bitset_t* part_neighbors = ctx.part_suffix_neighbors[level].rows
    cdef int new_level = level
    cdef long vertex
    cdef long other_vertex
    cdef long part

    bitset_intersection(ctx.greedy_changed_vertices, ctx.graph.rows[last_vertex], suffix_vertices)
    bitset_clear(ctx.greedy_changed_parts)
    bitset_add(ctx.greedy_changed_parts, ctx.part_of[last_vertex])
    for part in range(parts_used):
        if bitset_in(ctx.part_neighbors.rows[part], last_vertex):
            bitset_add(ctx.greedy_changed_parts, part)

    while True:
        vertex = bitset_first(ctx.greedy_changed_vertices)
        if vertex != -1:
            bitset_discard(ctx.greedy_changed_vertices, vertex)
            part = _find_greedy_part_for_vertex(vertex_neighbors[vertex], part_neighbors, parts_used, vertex)
        else:
            part = bitset_first(ctx.greedy_changed_parts)
            if part == -1:
                break
            bitset_discard(ctx.greedy_changed_parts, part)
            vertex = _find_greedy_vertex_for_part(ctx, part_neighbors[part], vertex_neighbors, suffix_vertices)
        if vertex == -1 or part == -1:
            continue

        bitset_discard(suffix_vertices, vertex)
        ctx.prefix[new_level] = vertex
        ctx.part_of[vertex] = part
        new_level += 1
        bitset_add(ctx.greedy_changed_parts, part)

        other_vertex = bitset_next(ctx.graph.rows[vertex], 0)
        while other_vertex != -1:
            if bitset_in(suffix_vertices, other_vertex):
                bitset_discard(vertex_neighbors[other_vertex], vertex)
                bitset_add(ctx.greedy_changed_vertices, other_vertex)
            other_vertex = bitset_next(ctx.graph.rows[vertex], other_vertex + 1)
        bitset_intersection(ctx.greedy_changed_vertices, ctx.greedy_changed_vertices, suffix_vertices)
        for part in range(parts_used):
            if bitset_in(part_neighbors[part], vertex):
                bitset_discard(part_neighbors[part], vertex)
                bitset_add(ctx.greedy_changed_parts, part)

    return new_level


cdef inline long _find_greedy_vertex_for_part(
    _Context ctx,
    bitset_t part_neighbors,
    bitset_t* vertex_neighbors,
    bitset_t suffix_vertices,
) noexcept:
    """A suffix vertex with the same suffix neighbors as the part, ignoring itself, or -1.

    Such a vertex is a suffix neighbor of the part or adjacent to all of them, so
    if the part has any, only the first one and its neighbors are tried.
    """
    cdef long vertex = bitset_first(part_neighbors)
    if vertex == -1:
        bitset_copy(ctx.greedy_candidates, suffix_vertices)
    else:
        bitset_intersection(ctx.greedy_candidates, ctx.graph.rows[vertex], suffix_vertices)
        bitset_add(ctx.greedy_candidates, vertex)
    vertex = bitset_next(ctx.greedy_candidates, 0)
    while vertex != -1:
        if _is_equal_ignoring(part_neighbors, vertex_neighbors[vertex], vertex):
            return vertex
        vertex = bitset_next(ctx.greedy_candidates, vertex + 1)
    return -1


cdef inline int _find_greedy_part_for_vertex(
    bitset_t vertex_neighbors,
    bitset_t* part_neighbors,
    int parts_used,
    int vertex,
) noexcept:
    """First part with the same suffix neighbors as `vertex`, ignoring `vertex` itself, or -1."""
    cdef int part
    for part in range(parts_used):
        if _is_equal_ignoring(part_neighbors[part], vertex_neighbors, vertex):
            return part
    return -1


cdef inline bint _check_state_seen(
    _Context ctx,
    bitset_t suffix_vertices,
    int level,
    int parts_used,
) noexcept:
    """Whether a node with the same suffix and the same parts was already searched.

    Parts are compared by their suffix neighbors, which are all that matters for
    the rest of the search, and regardless of their order.
    """
    if level > ctx.max_prefix_length or not ctx.optimizations & _SEEN_STATES:
        return False
    return ctx.seen_states.contains_or_add(
        suffix_vertices,
        ctx.part_suffix_neighbors[level].rows,
        parts_used,
    )


cdef inline void _update_part_neighbors(
    bitset_t neighbors_of_part,
    bitset_t previous_neighbors_of_part,
    bitset_t neighbors_of_vertex
) noexcept:
    bitset_copy(previous_neighbors_of_part, neighbors_of_part)
    bitset_union(neighbors_of_part, neighbors_of_part, neighbors_of_vertex)


cdef inline void _undo_update_part_neighbors(
    bitset_t neighbors_of_part,
    bitset_t previous_neighbors_of_part
) noexcept:
    bitset_copy(neighbors_of_part, previous_neighbors_of_part)

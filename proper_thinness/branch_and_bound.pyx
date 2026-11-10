import itertools

from sage.graphs.graph import Graph
from sage.data_structures.binary_matrix cimport *
from sage.graphs.base.static_dense_graph cimport dense_graph_init
from cysignals.memory cimport sig_malloc, sig_calloc, sig_free
from cysignals.signals cimport sig_on, sig_off

from thinness.branch_and_bound import calculate_thinness
from thinness.consistent_solution import ConsistentSolution
from thinness.seen_states cimport SeenStates
from proper_thinness import branch_and_bound_64
from proper_thinness.heuristic import heuristic_solution
from proper_thinness.optimizations import ALL_OPTIMIZATIONS, Optimization

DEFAULT_MAX_PREFIX_LENGTH = 15
DEFAULT_MAX_SEEN_ENTRIES = 1_000_000
# Graphs with at most this many vertices are searched with 64-bit words instead of bitsets.
MAX_VERTICES_FOR_WORDS = branch_and_bound_64.MAX_VERTICES

cdef int _SYMMETRY = Optimization.SYMMETRY
cdef int _SEEN_STATES = Optimization.SEEN_STATES
cdef int _GREEDY_EXISTING_PART = Optimization.GREEDY_EXISTING_PART
cdef int _GREEDY_NEW_PART = Optimization.GREEDY_NEW_PART
cdef int _PART_DOMINANCE = Optimization.PART_DOMINANCE


def calculate_proper_thinness(
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
    branch and bound searched, and its `'thinness_nodes'` to those searched to
    compute the thinness, with `Optimization.THINNESS_LOWER_BOUND`.
    """
    if statistics is not None:
        statistics['nodes'] = 0
        statistics['thinness_nodes'] = 0
    if optimizations & Optimization.COMPONENTS:
        components = [graph.subgraph(component, immutable=False) for component in graph.connected_components(sort=False)]
    else:
        components = [graph.copy(immutable=False)]
    relabellings = [component.relabel(return_map=True) for component in components]
    solutions = [
        calculate_proper_thinness_of_connected_graph(
            component,
            lower_bound,
            upper_bound,
            certificate,
            max_prefix_length,
            max_seen_entries,
            optimizations,
            statistics,
        ) for component in components
    ]

    if certificate:
        return _join_solutions(solutions, relabellings)
    else:
        return max(solutions)


def _join_solutions(solutions: list[ConsistentSolution], relabellings: list[dict]) -> ConsistentSolution:
    order = _join_orders([solution.order for solution in solutions], relabellings)
    partition = _join_partitions([solution.partition for solution in solutions], relabellings)
    return ConsistentSolution(order, partition)


def _join_orders(orders: list[list[int]], relabellings: list[dict]) -> list[int]:
    orders = [
        [_original_label(vertex, relabellings[i]) for vertex in order]
        for i, order in enumerate(orders)
    ]
    return list(itertools.chain.from_iterable(orders))


def _join_partitions(partitions: list[list[set]], relabellings: list[dict]) -> list[set]:
    partitions = [
        [set(_original_label(vertex, relabellings[i]) for vertex in part) for part in partition]
        for i, partition in enumerate(partitions)
    ]
    return [
        set(itertools.chain.from_iterable(parts))
        for parts in itertools.zip_longest(*partitions, fillvalue=set())
    ]


def _original_label(vertex: int, relabelling: dict):
    return next(key for key, value in relabelling.items() if value == vertex)



def calculate_proper_thinness_of_connected_graph(
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

    The proper thinness is at least the thinness, which is used as lower bound
    with `Optimization.THINNESS_LOWER_BOUND`. With `Optimization.HEURISTIC_UPPER_BOUND`,
    a solution found heuristically gives an upper bound, and is returned if the
    search doesn't find a better one. The order of the thinness solution is one
    of the orders the heuristic tries. Without `Optimization.COMPONENTS`, the
    graph doesn't need to be connected. If `statistics` is given, the nodes
    searched are added to its `'nodes'`, and those searched to compute the
    thinness to its `'thinness_nodes'`.
    """
    extra_orders = []
    if optimizations & Optimization.THINNESS_LOWER_BOUND:
        thinness_statistics = {}
        thinness_solution = calculate_thinness(graph, certificate=True, statistics=thinness_statistics)
        if statistics is not None:
            statistics['thinness_nodes'] = statistics.get('thinness_nodes', 0) + thinness_statistics['nodes']
        lower_bound = max(lower_bound, thinness_solution.thinness)
        extra_orders.append(thinness_solution.order)
    if optimizations & Optimization.HEURISTIC_UPPER_BOUND:
        heuristic = heuristic_solution(graph, extra_orders)
    else:
        # Every vertex on its own part is a solution.
        heuristic = ConsistentSolution(list(graph), [{vertex} for vertex in graph])
    if heuristic.thinness <= lower_bound:
        return heuristic if certificate else heuristic.thinness
    upper_bound = heuristic.thinness if upper_bound is None else min(upper_bound, heuristic.thinness)

    search = (
        branch_and_bound_64.search
        if graph.order() <= MAX_VERTICES_FOR_WORDS
        else _search_with_bitsets
    )
    branch_and_bound_proper_thinness, best_order, best_partition, nodes = search(
        graph,
        lower_bound,
        upper_bound - 1,
        max_prefix_length,
        max_seen_entries,
        optimizations,
    )
    if statistics is not None:
        statistics['nodes'] = statistics.get('nodes', 0) + nodes

    cdef int proper_thinness = branch_and_bound_proper_thinness if branch_and_bound_proper_thinness != -1 else upper_bound
    cdef list partition
    if certificate:
        if branch_and_bound_proper_thinness == -1:
            return heuristic
        partition = [set() for _ in range(proper_thinness)]
        for vertex, part in enumerate(best_partition):
            partition[part].add(vertex)
        return ConsistentSolution(best_order, partition)
    else:
        return proper_thinness


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
        parts_used=0,
        lower_bound=lower_bound,
        upper_bound=upper_bound,
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

    The arrays of matrices `*_by_level` have one matrix per prefix length, so that each node of the search keeps its own while its
    children run.
    """
    cdef int n
    cdef binary_matrix_t graph
    cdef int* prefix
    cdef int* part_of
    cdef bitset_t all_vertices
    cdef bitset_t prefix_vertices
    cdef binary_matrix_t new_suffixes
    cdef binary_matrix_t part_neighbors
    cdef binary_matrix_t previous_part_neighbors
    cdef binary_matrix_t parts_for_vertices
    cdef binary_matrix_t forbidden_parts_for_vertices
    cdef binary_matrix_t vertices_forbidden_by_vertex
    cdef binary_matrix_t* vertex_suffix_neighbors_by_level
    cdef binary_matrix_t* part_suffix_neighbors_by_level
    cdef binary_matrix_t* part_forbidden_vertices_by_level
    cdef bint* part_forbidden_vertices_computed
    cdef bitset_t forbidden_vertices_union
    cdef bitset_t prefix_non_neighbors_of_vertex
    cdef bitset_t newly_forbidden_vertices
    cdef binary_matrix_t part_states
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
        cdef int i
        self.n = n

        self.prefix = <int*>sig_malloc(sizeof(int) * n)
        self.part_of = <int*>sig_malloc(sizeof(int) * n)

        bitset_init(self.all_vertices, n)
        bitset_complement(self.all_vertices, self.all_vertices)

        bitset_init(self.prefix_vertices, n)
        binary_matrix_init(self.new_suffixes, n+1, n)
        binary_matrix_init(self.part_neighbors, max_parts, n)
        binary_matrix_init(self.previous_part_neighbors, n, n)
        binary_matrix_init(self.parts_for_vertices, n, max_parts)
        binary_matrix_init(self.forbidden_parts_for_vertices, n, max_parts)

        binary_matrix_init(self.vertices_forbidden_by_vertex, n, n)

        # Zeroed so that __dealloc__ can free them even if an init below fails.
        self.vertex_suffix_neighbors_by_level = <binary_matrix_t*>sig_calloc(n + 1, sizeof(binary_matrix_t))
        self.part_suffix_neighbors_by_level = <binary_matrix_t*>sig_calloc(n + 1, sizeof(binary_matrix_t))
        self.part_forbidden_vertices_by_level = <binary_matrix_t*>sig_calloc(n + 1, sizeof(binary_matrix_t))
        self.part_forbidden_vertices_computed = <bint*>sig_calloc(n + 1, sizeof(bint))
        for i in range(n + 1):
            binary_matrix_init(self.vertex_suffix_neighbors_by_level[i], n, n)
            binary_matrix_init(self.part_suffix_neighbors_by_level[i], max_parts, n)
            binary_matrix_init(self.part_forbidden_vertices_by_level[i], max_parts, n)
        bitset_init(self.forbidden_vertices_union, n)
        bitset_init(self.prefix_non_neighbors_of_vertex, n)
        bitset_init(self.newly_forbidden_vertices, n)
        binary_matrix_init(self.part_states, 2 * max_parts, n)

        self.seen_states = SeenStates(self.all_vertices.limbs, max_parts, max_seen_entries, sets_per_part=2)

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
        cdef int i
        binary_matrix_free(self.graph)
        sig_free(self.prefix)
        sig_free(self.part_of)
        bitset_free(self.all_vertices)
        bitset_free(self.prefix_vertices)
        binary_matrix_free(self.new_suffixes)
        binary_matrix_free(self.part_neighbors)
        binary_matrix_free(self.previous_part_neighbors)
        binary_matrix_free(self.parts_for_vertices)
        binary_matrix_free(self.forbidden_parts_for_vertices)
        binary_matrix_free(self.vertices_forbidden_by_vertex)
        if self.vertex_suffix_neighbors_by_level != NULL:
            for i in range(self.n + 1):
                binary_matrix_free(self.vertex_suffix_neighbors_by_level[i])
            sig_free(self.vertex_suffix_neighbors_by_level)
        if self.part_suffix_neighbors_by_level != NULL:
            for i in range(self.n + 1):
                binary_matrix_free(self.part_suffix_neighbors_by_level[i])
            sig_free(self.part_suffix_neighbors_by_level)
        if self.part_forbidden_vertices_by_level != NULL:
            for i in range(self.n + 1):
                binary_matrix_free(self.part_forbidden_vertices_by_level[i])
            sig_free(self.part_forbidden_vertices_by_level)
        sig_free(self.part_forbidden_vertices_computed)
        bitset_free(self.forbidden_vertices_union)
        bitset_free(self.prefix_non_neighbors_of_vertex)
        bitset_free(self.newly_forbidden_vertices)
        binary_matrix_free(self.part_states)
        bitset_free(self.canonical_vertices)
        sig_free(self.best_order)
        sig_free(self.best_partition)


cdef inline void _build_canonical_vertices(graph: Graph, bitset_t canonical_vertices):
    cdef list orbit
    for orbit in graph.automorphism_group(orbits=True, return_group=False):
        bitset_add(canonical_vertices, <int> orbit[0])


cdef int _branch_and_bound(
    _Context ctx,
    bitset_t suffix_vertices,
    int parts_used,
    int lower_bound,
    int upper_bound,
):
    """upper_bound is inclusive"""
    ctx.nodes += 1
    cdef int level = _get_level(suffix_vertices)

    cdef bitset_t new_suffix = ctx.new_suffixes.rows[level]
    bitset_copy(new_suffix, suffix_vertices)

    if bitset_isempty(new_suffix) and parts_used <= upper_bound:
        _store_best_solution(ctx)
        return parts_used

    # Checked before the greedy step too, which is the same for the same state, so
    # that nodes already searched don't pay for it.
    if _check_state_seen(ctx, new_suffix, level, parts_used):
        return -1

    # The suffix neighbors of this node are kept up to date at the level it started
    # at, which no ancestor uses, as they all keep theirs at shorter prefixes.
    cdef int entry_level = level
    level = _increment_prefix_greedily_on_existing_parts(ctx, new_suffix, level, parts_used)

    if level != entry_level:
        if bitset_isempty(new_suffix) and parts_used <= upper_bound:
            _store_best_solution(ctx)
            return parts_used

        if _check_state_seen(ctx, new_suffix, level, parts_used):
            return -1

    cdef int best_solution_found = _branch_adding_to_existing_part(
        ctx,
        new_suffix,
        entry_level,
        parts_used,
        lower_bound,
        upper_bound,
    )

    if best_solution_found != -1:
        if best_solution_found <= lower_bound:
            return best_solution_found
        else:
            upper_bound = best_solution_found - 1

    cdef int new_part_solution
    cdef int part
    if parts_used < upper_bound:
        parts_used += 1
        part = parts_used - 1
        lower_bound = max(lower_bound, parts_used)

        if ctx.optimizations & _GREEDY_NEW_PART and _add_vertex_to_prefix_greedily_on_part(
            ctx, part, new_suffix, level, entry_level,
        ):
            new_part_solution = _branch_and_bound(
                ctx,
                new_suffix,
                parts_used,
                lower_bound,
                upper_bound,
            )
        else:
            new_part_solution = _branch_adding_to_new_part(
                ctx,
                new_suffix,
                parts_used,
                lower_bound,
                upper_bound,
            )

        if new_part_solution != -1:
            best_solution_found = new_part_solution

    return best_solution_found


cdef inline void _store_best_solution(_Context ctx):
    _copy_array(ctx.n, ctx.prefix, ctx.best_order)
    _copy_array(ctx.n, ctx.part_of, ctx.best_partition)


cdef inline int _get_level(bitset_t suffix_vertices):
    return suffix_vertices.size - bitset_len(suffix_vertices)


cdef inline void _copy_array(int n, int* array_from, int* array_to):
    for i in range(n):
        array_to[i] = array_from[i]


cdef inline int _branch_adding_to_existing_part(
    _Context ctx,
    bitset_t suffix_vertices,
    int neighbors_level,
    int parts_used,
    int lower_bound,
    int upper_bound,
):
    cdef int level = _get_level(suffix_vertices)
    cdef int best_solution_found = -1
    cdef bitset_s* parts_for_vertex
    cdef int part
    cdef int vertex = bitset_next(suffix_vertices, 0)
    while vertex != -1:
        bitset_discard(suffix_vertices, vertex)
        ctx.prefix[level] = vertex

        parts_for_vertex = _get_available_parts_for_vertex(
            ctx,
            vertex,
            neighbors_level,
            parts_used,
            suffix_vertices,
        )
        part = bitset_next(parts_for_vertex, 0)
        while part != -1:
            current_solution = _branch_with_vertex_on_part(
                ctx,
                vertex,
                part,
                suffix_vertices,
                parts_used,
                lower_bound,
                upper_bound,
            )

            if current_solution != -1:
                best_solution_found = current_solution
                if best_solution_found <= lower_bound:
                    return best_solution_found
                else:
                    upper_bound = best_solution_found - 1
            part = bitset_next(parts_for_vertex, part + 1)

        bitset_add(suffix_vertices, vertex)
        vertex = bitset_next(suffix_vertices, vertex + 1)

    return best_solution_found


cdef inline bitset_s* _get_available_parts_for_vertex(
    _Context ctx,
    int vertex,
    int neighbors_level,
    int parts_used,
    bitset_t suffix_vertices,
):
    """Parts that `vertex` can be added to if it is the next vertex of the prefix.

    `vertex` is not in suffix. The suffix neighbors and forbidden vertices are the
    ones stored at `neighbors_level`, which are those of the suffix with `vertex`,
    so `vertex` is ignored when comparing them. Of the parts that dominate each
    other, only one is kept, see `_is_part_dominated`.
    """
    cdef bitset_s* vertex_neighbors = ctx.vertex_suffix_neighbors_by_level[neighbors_level].rows[vertex]
    cdef bitset_t* part_neighbors = ctx.part_suffix_neighbors_by_level[neighbors_level].rows
    cdef bitset_s* parts_for_vertex = ctx.parts_for_vertices.rows[vertex]
    cdef int part
    cdef int other_part
    bitset_clear(parts_for_vertex)
    for part in range(parts_used):
        if _is_subset_ignoring(part_neighbors[part], vertex_neighbors, vertex):
            bitset_add(parts_for_vertex, part)
    bitset_difference(parts_for_vertex, parts_for_vertex, ctx.forbidden_parts_for_vertices.rows[vertex])
    if not ctx.optimizations & _PART_DOMINANCE:
        return parts_for_vertex

    cdef bint newly_forbidden_vertices_computed = False
    part = bitset_next(parts_for_vertex, 0)
    while part != -1:
        other_part = bitset_next(parts_for_vertex, 0)
        while other_part != -1 and other_part < part:
            if _is_part_dominated(
                ctx, vertex, neighbors_level, parts_used, part, other_part, suffix_vertices,
                &newly_forbidden_vertices_computed,
            ):
                bitset_discard(parts_for_vertex, part)
                break
            elif _is_part_dominated(
                ctx, vertex, neighbors_level, parts_used, other_part, part, suffix_vertices,
                &newly_forbidden_vertices_computed,
            ):
                bitset_discard(parts_for_vertex, other_part)
            other_part = bitset_next(parts_for_vertex, other_part + 1)
        part = bitset_next(parts_for_vertex, part + 1)

    return parts_for_vertex


cdef inline bint _is_part_dominated(
    _Context ctx,
    int vertex,
    int neighbors_level,
    int parts_used,
    int part,
    int other_part,
    bitset_t suffix_vertices,
    bint* newly_forbidden_vertices_computed,
):
    """Whether adding `vertex` to `other_part` is always at least as good as adding it to `part`.

    Adding `vertex` to either part gives it the suffix neighbors of `vertex`, and
    forbids from it the newly forbidden vertices of `vertex`. It's at least as
    good to add it to `other_part` if, afterwards, each of the two parts has at
    most the suffix neighbors and forbidden vertices of the other one if `vertex`
    is added to `part` instead. That is, if `part` has at most the suffix
    neighbors and forbidden vertices of `other_part`, and the forbidden vertices
    of `other_part` are those of `part` plus at most some of the newly forbidden
    vertices of `vertex`. Both parts are available for `vertex`, which is not in
    suffix.
    """
    cdef bitset_t* part_neighbors = ctx.part_suffix_neighbors_by_level[neighbors_level].rows
    cdef bitset_t* part_forbidden_vertices = ctx.part_forbidden_vertices_by_level[neighbors_level].rows
    if not _is_subset_ignoring(part_neighbors[part], part_neighbors[other_part], vertex):
        return False
    if not ctx.part_forbidden_vertices_computed[neighbors_level]:
        _compute_part_forbidden_vertices(ctx, neighbors_level, suffix_vertices, vertex, parts_used)
    if not _is_subset_ignoring(part_forbidden_vertices[part], part_forbidden_vertices[other_part], vertex):
        return False
    if not newly_forbidden_vertices_computed[0]:
        _compute_newly_forbidden_vertices(ctx, vertex, suffix_vertices)
        newly_forbidden_vertices_computed[0] = True
    bitset_union(ctx.forbidden_vertices_union, part_forbidden_vertices[part], ctx.newly_forbidden_vertices)
    return _is_subset_ignoring(part_forbidden_vertices[other_part], ctx.forbidden_vertices_union, vertex)


cdef inline bint _is_subset_ignoring(bitset_t subset, bitset_t superset, int vertex):
    """Whether `subset` is a subset of `superset`, ignoring `vertex`."""
    if bitset_in(superset, vertex) or not bitset_in(subset, vertex):
        return bitset_issubset(subset, superset)
    bitset_discard(subset, vertex)
    cdef bint is_subset = bitset_issubset(subset, superset)
    bitset_add(subset, vertex)
    return is_subset


cdef inline int _branch_adding_to_new_part(
    _Context ctx,
    bitset_t suffix_vertices,
    int parts_used,
    int lower_bound,
    int upper_bound,
):
    cdef int level = _get_level(suffix_vertices)
    cdef int best_solution_found = -1
    cdef int part = parts_used - 1
    cdef bitset_s* vertices
    if level == 0:
        vertices = &ctx.canonical_vertices[0]
    else:
        vertices = &suffix_vertices[0]
    cdef int vertex = bitset_next(vertices, 0)
    while vertex != -1:
        bitset_discard(suffix_vertices, vertex)
        ctx.prefix[level] = vertex

        current_solution = _branch_with_vertex_on_part(
            ctx,
            vertex,
            part,
            suffix_vertices,
            parts_used,
            lower_bound,
            upper_bound,
        )

        if current_solution != -1:
            best_solution_found = current_solution
            if best_solution_found <= lower_bound:
                return best_solution_found
            else:
                upper_bound = best_solution_found - 1

        bitset_add(suffix_vertices, vertex)
        vertex = bitset_next(vertices, vertex + 1)

    return best_solution_found


cdef inline int _branch_with_vertex_on_part(
    _Context ctx,
    int vertex,
    int part,
    bitset_t suffix_vertices,
    int parts_used,
    int lower_bound,
    int upper_bound,
):
    ctx.part_of[vertex] = part

    _update_part_neighbors(
        ctx.part_neighbors.rows[part],
        ctx.previous_part_neighbors.rows[vertex],
        ctx.graph.rows[vertex]
    )

    _update_forbidden_parts_for_vertices(ctx, vertex, part, suffix_vertices)

    cdef int solution = _branch_and_bound(
        ctx,
        suffix_vertices,
        parts_used,
        lower_bound,
        upper_bound,
    )

    _undo_update_part_neighbors(
        ctx.part_neighbors.rows[part],
        ctx.previous_part_neighbors.rows[vertex]
    )

    _undo_update_forbidden_parts_for_vertices(ctx, vertex, part)

    return solution


cdef inline int _increment_prefix_greedily_on_existing_parts(
    _Context ctx,
    bitset_t suffix_vertices,
    int level,
    int parts_used,
):
    """Add to prefix all vertices that can be added to an existing part for free.

    Computes the suffix neighbors of the vertices and the parts at `level`, and
    keeps them up to date as vertices leave the suffix. Returns the new length of
    the prefix.
    """
    _compute_suffix_neighbors(ctx, suffix_vertices, level, parts_used)
    if not ctx.optimizations & _GREEDY_EXISTING_PART:
        return level
    cdef bitset_t* vertex_neighbors = ctx.vertex_suffix_neighbors_by_level[level].rows
    cdef bitset_t* part_neighbors = ctx.part_suffix_neighbors_by_level[level].rows
    cdef int new_level = level
    cdef int vertex
    cdef int other_vertex
    cdef int part
    cdef bint suffix_changed = True
    while suffix_changed:
        suffix_changed = False
        vertex = bitset_next(suffix_vertices, 0)
        while vertex != -1:
            bitset_discard(suffix_vertices, vertex)

            part = _find_free_part_for_vertex(ctx, vertex, level, suffix_vertices, parts_used)

            if part != -1:
                ctx.prefix[new_level] = vertex
                ctx.part_of[vertex] = part
                new_level += 1
                suffix_changed = True

                for part in range(parts_used):
                    bitset_discard(part_neighbors[part], vertex)
                other_vertex = bitset_next(suffix_vertices, 0)
                while other_vertex != -1:
                    bitset_discard(vertex_neighbors[other_vertex], vertex)
                    other_vertex = bitset_next(suffix_vertices, other_vertex + 1)
            else:
                bitset_add(suffix_vertices, vertex)

            vertex = bitset_next(suffix_vertices, vertex + 1)

    return new_level


cdef inline void _compute_suffix_neighbors(
    _Context ctx,
    bitset_t suffix_vertices,
    int level,
    int parts_used,
):
    """Suffix neighbors of the parts and of the suffix vertices, stored at `level`.

    The suffix vertices forbidden from each part are only computed when they are
    needed, by `_compute_part_forbidden_vertices`.
    """
    ctx.part_forbidden_vertices_computed[level] = False
    cdef int part
    for part in range(parts_used):
        bitset_intersection(
            ctx.part_suffix_neighbors_by_level[level].rows[part],
            ctx.part_neighbors.rows[part],
            suffix_vertices
        )
    cdef int vertex = bitset_next(suffix_vertices, 0)
    while vertex != -1:
        bitset_intersection(
            ctx.vertex_suffix_neighbors_by_level[level].rows[vertex],
            ctx.graph.rows[vertex],
            suffix_vertices
        )
        vertex = bitset_next(suffix_vertices, vertex + 1)


cdef inline void _compute_part_forbidden_vertices(
    _Context ctx,
    int level,
    bitset_t suffix_vertices,
    int vertex,
    int parts_used,
):
    """Suffix vertices forbidden from each part, stored at `level`.

    `vertex` is not in suffix, but the suffix of the node has it too.
    """
    cdef bitset_t* part_forbidden_vertices = ctx.part_forbidden_vertices_by_level[level].rows
    cdef int part
    for part in range(parts_used):
        bitset_clear(part_forbidden_vertices[part])
    bitset_add(suffix_vertices, vertex)
    cdef int suffix_vertex = bitset_next(suffix_vertices, 0)
    while suffix_vertex != -1:
        part = bitset_next(ctx.forbidden_parts_for_vertices.rows[suffix_vertex], 0)
        while part != -1:
            bitset_add(part_forbidden_vertices[part], suffix_vertex)
            part = bitset_next(ctx.forbidden_parts_for_vertices.rows[suffix_vertex], part + 1)
        suffix_vertex = bitset_next(suffix_vertices, suffix_vertex + 1)
    bitset_discard(suffix_vertices, vertex)
    ctx.part_forbidden_vertices_computed[level] = True


cdef inline bint _add_vertex_to_prefix_greedily_on_part(
    _Context ctx,
    int part,
    bitset_t suffix_vertices,
    int level,
    int neighbors_level,
):
    """Add to the new, empty `part` a vertex that can be added to it for free, if there is one.

    As the part has no suffix neighbors, the vertex can't have any either. The
    suffix neighbors of the vertices are the ones stored at `neighbors_level`.
    """
    cdef bitset_t* vertex_neighbors = ctx.vertex_suffix_neighbors_by_level[neighbors_level].rows
    cdef int vertex = bitset_next(suffix_vertices, 0)
    while vertex != -1:
        if (
            bitset_isempty(vertex_neighbors[vertex])
            and not bitset_in(ctx.forbidden_parts_for_vertices.rows[vertex], part)
        ):
            bitset_discard(suffix_vertices, vertex)
            _compute_newly_forbidden_vertices(ctx, vertex, suffix_vertices)
            if _are_forbidden_from_part(ctx, ctx.newly_forbidden_vertices, part):
                ctx.prefix[level] = vertex
                ctx.part_of[vertex] = part
                return True
            bitset_add(suffix_vertices, vertex)
        vertex = bitset_next(suffix_vertices, vertex + 1)

    return False


cdef inline int _find_free_part_for_vertex(
    _Context ctx,
    int vertex,
    int level,
    bitset_t suffix_vertices,
    int parts_used,
):
    """First part that `vertex` can be added to for free, or -1.

    `vertex` is not in suffix, and the suffix neighbors stored at `level` are
    those of the suffix with `vertex`, so `vertex` is ignored when comparing them.
    Adding it to a part is free if the part is not forbidden for it, its suffix
    neighbors are the same as the part's, and every suffix vertex that it would
    forbid from the part is already forbidden from it. Then the suffix neighbors
    and the forbidden parts don't change, and any solution can be changed to have
    `vertex` next on that part.
    """
    cdef bitset_s* vertex_neighbors = ctx.vertex_suffix_neighbors_by_level[level].rows[vertex]
    cdef bitset_t* part_neighbors = ctx.part_suffix_neighbors_by_level[level].rows
    cdef bint newly_forbidden_vertices_computed = False
    cdef int part
    for part in range(parts_used):
        if bitset_in(ctx.forbidden_parts_for_vertices.rows[vertex], part):
            continue
        if not _is_equal_ignoring(part_neighbors[part], vertex_neighbors, vertex):
            continue
        if not newly_forbidden_vertices_computed:
            _compute_newly_forbidden_vertices(ctx, vertex, suffix_vertices)
            newly_forbidden_vertices_computed = True
        if _are_forbidden_from_part(ctx, ctx.newly_forbidden_vertices, part):
            return part
    return -1


cdef inline bint _is_equal_ignoring(bitset_t first, bitset_t second, int vertex):
    """Whether `first` and `second` are equal, ignoring `vertex`."""
    if bitset_in(first, vertex) == bitset_in(second, vertex):
        return bitset_eq(first, second)
    bitset_flip(first, vertex)
    cdef bint is_equal = bitset_eq(first, second)
    bitset_flip(first, vertex)
    return is_equal


cdef inline bint _are_forbidden_from_part(_Context ctx, bitset_t vertices, int part):
    cdef int vertex = bitset_next(vertices, 0)
    while vertex != -1:
        if not bitset_in(ctx.forbidden_parts_for_vertices.rows[vertex], part):
            return False
        vertex = bitset_next(vertices, vertex + 1)
    return True


cdef inline bint _check_state_seen(
    _Context ctx,
    bitset_t suffix_vertices,
    int level,
    int parts_used,
):
    """Whether a node with the same suffix and the same parts was already searched.

    All that matters of a part for the rest of the search are its suffix
    neighbors and the suffix vertices that can't be added to it. Parts are
    compared by those, regardless of their order.
    """
    if level > ctx.max_prefix_length or not ctx.optimizations & _SEEN_STATES:
        return False
    _build_part_states(ctx, suffix_vertices, parts_used)
    return ctx.seen_states.contains_or_add(suffix_vertices, ctx.part_states.rows, parts_used)


cdef inline void _build_part_states(
    _Context ctx,
    bitset_t suffix_vertices,
    int parts_used,
):
    """For each part, its suffix neighbors and the suffix vertices that are forbidden from it."""
    cdef int part
    for part in range(parts_used):
        bitset_intersection(ctx.part_states.rows[2 * part], ctx.part_neighbors.rows[part], suffix_vertices)
        bitset_clear(ctx.part_states.rows[2 * part + 1])
    cdef int vertex = bitset_next(suffix_vertices, 0)
    while vertex != -1:
        part = bitset_next(ctx.forbidden_parts_for_vertices.rows[vertex], 0)
        while part != -1:
            bitset_add(ctx.part_states.rows[2 * part + 1], vertex)
            part = bitset_next(ctx.forbidden_parts_for_vertices.rows[vertex], part + 1)
        vertex = bitset_next(suffix_vertices, vertex + 1)


cdef inline void _update_part_neighbors(
    bitset_t neighbors_of_part,
    bitset_t previous_neighbors_of_part,
    bitset_t neighbors_of_vertex
):
    bitset_copy(previous_neighbors_of_part, neighbors_of_part)
    bitset_union(neighbors_of_part, neighbors_of_part, neighbors_of_vertex)


cdef inline void _undo_update_part_neighbors(
    bitset_t neighbors_of_part,
    bitset_t previous_neighbors_of_part
):
    bitset_copy(neighbors_of_part, previous_neighbors_of_part)


cdef inline void _compute_newly_forbidden_vertices(
    _Context ctx,
    int new_vertex,
    bitset_t suffix_vertices,
):
    """Suffix vertices that can't be in the part of `new_vertex`, if it's the last vertex of the prefix.

    Those are the ones adjacent to a prefix vertex that isn't adjacent to
    `new_vertex`. They are stored in `ctx.newly_forbidden_vertices`.
    """
    bitset_complement(ctx.prefix_vertices, suffix_vertices)
    bitset_complement(ctx.prefix_non_neighbors_of_vertex, ctx.graph.rows[new_vertex])
    bitset_discard(ctx.prefix_non_neighbors_of_vertex, new_vertex)
    bitset_intersection(ctx.prefix_non_neighbors_of_vertex, ctx.prefix_non_neighbors_of_vertex, ctx.prefix_vertices)
    bitset_clear(ctx.newly_forbidden_vertices)
    cdef int prefix_non_neighbor = bitset_next(ctx.prefix_non_neighbors_of_vertex, 0)
    while prefix_non_neighbor != -1:
        bitset_union(
            ctx.newly_forbidden_vertices,
            ctx.newly_forbidden_vertices,
            ctx.graph.rows[prefix_non_neighbor]
        )
        prefix_non_neighbor = bitset_next(ctx.prefix_non_neighbors_of_vertex, prefix_non_neighbor + 1)
    bitset_intersection(ctx.newly_forbidden_vertices, ctx.newly_forbidden_vertices, suffix_vertices)


cdef inline void _update_forbidden_parts_for_vertices(
    _Context ctx,
    int new_vertex,
    int part_of_new_vertex,
    bitset_t suffix_vertices,
):
    """Forbid the part of `new_vertex` for the suffix vertices that can't go after it in it.

    The vertices that didn't have it forbidden yet are stored in
    `ctx.vertices_forbidden_by_vertex.rows[new_vertex]`, to undo it.
    """
    _compute_newly_forbidden_vertices(ctx, new_vertex, suffix_vertices)
    cdef bitset_s* vertices_forbidden = ctx.vertices_forbidden_by_vertex.rows[new_vertex]
    bitset_clear(vertices_forbidden)
    cdef int vertex = bitset_next(ctx.newly_forbidden_vertices, 0)
    while vertex != -1:
        if not bitset_in(ctx.forbidden_parts_for_vertices.rows[vertex], part_of_new_vertex):
            bitset_add(ctx.forbidden_parts_for_vertices.rows[vertex], part_of_new_vertex)
            bitset_add(vertices_forbidden, vertex)
        vertex = bitset_next(ctx.newly_forbidden_vertices, vertex + 1)


cdef inline void _undo_update_forbidden_parts_for_vertices(
    _Context ctx,
    int new_vertex,
    int part_of_new_vertex,
):
    cdef bitset_s* vertices_forbidden = ctx.vertices_forbidden_by_vertex.rows[new_vertex]
    cdef int vertex = bitset_next(vertices_forbidden, 0)
    while vertex != -1:
        bitset_discard(ctx.forbidden_parts_for_vertices.rows[vertex], part_of_new_vertex)
        vertex = bitset_next(vertices_forbidden, vertex + 1)

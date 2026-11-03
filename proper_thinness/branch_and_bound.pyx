import itertools
from multiset import Multiset, FrozenMultiset

from sage.graphs.graph import Graph
from sage.data_structures.binary_matrix cimport *
from sage.graphs.base.static_dense_graph cimport dense_graph_init
from cysignals.memory cimport sig_malloc, sig_calloc, sig_free
from cysignals.signals cimport sig_on, sig_off

from thinness.consistent_solution import ConsistentSolution

DEFAULT_MAX_PREFIX_LENGTH = 15
DEFAULT_MAX_SEEN_ENTRIES = 1_000_000


def calculate_proper_thinness(
    graph: Graph,
    lower_bound: int = 1,
    upper_bound: int = None,
    certificate: bool = False,
    max_prefix_length: int = DEFAULT_MAX_PREFIX_LENGTH,
    max_seen_entries: int = DEFAULT_MAX_SEEN_ENTRIES
) -> ConsistentSolution | int:
    components = [graph.subgraph(component, immutable=False) for component in graph.connected_components(sort=False)]
    relabellings = [component.relabel(return_map=True) for component in components]
    solutions = [
        calculate_proper_thinness_of_connected_graph(
            component,
            lower_bound,
            upper_bound,
            certificate,
            max_prefix_length,
            max_seen_entries
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
    max_seen_entries: int = DEFAULT_MAX_SEEN_ENTRIES
) -> ConsistentSolution | int:
    """upper_bound is exclusive."""
    if upper_bound is None:
        upper_bound = graph.order() + 1

    cdef int max_branch_and_bound_proper_thinness = upper_bound - 1

    cdef _Context ctx = _Context(
        graph,
        max_branch_and_bound_proper_thinness,
        max_prefix_length,
        max_seen_entries,
    )

    sig_on()
    branch_and_bound_proper_thinness = _branch_and_bound(
        ctx,
        suffix_vertices=ctx.all_vertices,
        parts_used=0,
        lower_bound=lower_bound,
        upper_bound=max_branch_and_bound_proper_thinness,
    )
    sig_off()

    cdef int proper_thinness = branch_and_bound_proper_thinness if branch_and_bound_proper_thinness != -1 else upper_bound
    cdef list order
    cdef list partition
    if certificate:
        order = [ctx.best_order[i] for i in range(ctx.n)]
        partition = [set() for _ in range(proper_thinness)]
        for vertex in range(ctx.n):
            partition[ctx.best_partition[vertex]].add(vertex)
        return ConsistentSolution(order, partition)
    else:
        return proper_thinness


cdef class _Context:
    """State shared by every call of the branch and bound recursion.

    Holds the graph, the scratch buffers and the search settings, so that the
    recursive functions only receive the values that change between calls.
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
    cdef binary_matrix_t* previous_forbidden_parts_for_vertices
    cdef bitset_t suffix_neighbors_of_vertex
    cdef binary_matrix_t part_suffix_neighbors
    cdef bitset_t prefix_non_neighbors_of_vertex
    cdef dict seen_states
    cdef int seen_entries
    cdef bitset_t canonical_vertices
    cdef int* best_order
    cdef int* best_partition
    cdef int max_prefix_length
    cdef int max_seen_entries

    def __cinit__(
        self,
        graph: Graph,
        int max_parts,
        int max_prefix_length,
        int max_seen_entries,
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

        # Zeroed so that __dealloc__ can free it even if an init below fails.
        self.previous_forbidden_parts_for_vertices = <binary_matrix_t*>sig_calloc(n, sizeof(binary_matrix_t))
        for i in range(n):
            binary_matrix_init(self.previous_forbidden_parts_for_vertices[i], n, max_parts)

        bitset_init(self.suffix_neighbors_of_vertex, n)
        binary_matrix_init(self.part_suffix_neighbors, max_parts, n)
        bitset_init(self.prefix_non_neighbors_of_vertex, n)

        self.seen_states = dict()
        self.seen_entries = 0

        bitset_init(self.canonical_vertices, n)
        _build_canonical_vertices(graph, self.canonical_vertices)

        self.best_order = <int*>sig_malloc(sizeof(int) * n)
        self.best_partition = <int*>sig_malloc(sizeof(int) * n)

        self.max_prefix_length = max_prefix_length
        self.max_seen_entries = max_seen_entries

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
        if self.previous_forbidden_parts_for_vertices != NULL:
            for i in range(self.n):
                binary_matrix_free(self.previous_forbidden_parts_for_vertices[i])
            sig_free(self.previous_forbidden_parts_for_vertices)
        bitset_free(self.suffix_neighbors_of_vertex)
        binary_matrix_free(self.part_suffix_neighbors)
        bitset_free(self.prefix_non_neighbors_of_vertex)
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
    cdef int level = _get_level(suffix_vertices)

    cdef bitset_t new_suffix = ctx.new_suffixes.rows[level]
    bitset_copy(new_suffix, suffix_vertices)

    # _increment_prefix_greedily_on_existing_parts(ctx, new_suffix, parts_used)

    if bitset_isempty(new_suffix) and parts_used <= upper_bound:
        _copy_array(ctx.n, ctx.prefix, ctx.best_order)
        _copy_array(ctx.n, ctx.part_of, ctx.best_partition)
        return parts_used

    # if _check_state_seen(ctx, new_suffix, parts_used):
    #     return -1

    cdef int best_solution_found = _branch_adding_to_existing_part(
        ctx,
        new_suffix,
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
    cdef int vertex_added_on_new_part
    if parts_used < upper_bound:
        parts_used += 1
        part = parts_used - 1
        lower_bound = max(lower_bound, parts_used)
        # Update this later
        # vertex_added_on_new_part = _add_vertex_to_prefix_greedily_on_part(ctx, part, new_suffix)
        vertex_added_on_new_part = False

        if vertex_added_on_new_part:
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


cdef inline int _get_level(bitset_t suffix_vertices):
    return suffix_vertices.size - bitset_len(suffix_vertices)


cdef inline void _copy_array(int n, int* array_from, int* array_to):
    for i in range(n):
        array_to[i] = array_from[i]


cdef inline int _branch_adding_to_existing_part(
    _Context ctx,
    bitset_t suffix_vertices,
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

        parts_for_vertex = _get_available_parts_for_vertex(ctx, vertex, parts_used, suffix_vertices)
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
    int parts_used,
    bitset_t suffix_vertices,
):
    """`vertex` is not in suffix."""
    bitset_intersection(ctx.suffix_neighbors_of_vertex, ctx.graph.rows[vertex], suffix_vertices)

    cdef bitset_s* parts_for_vertex = ctx.parts_for_vertices.rows[vertex]
    bitset_clear(parts_for_vertex)
    for part in range(parts_used):
        bitset_intersection(
            ctx.part_suffix_neighbors.rows[part],
            ctx.part_neighbors.rows[part],
            suffix_vertices
        )
        if bitset_issubset(ctx.part_suffix_neighbors.rows[part], ctx.suffix_neighbors_of_vertex):
            bitset_add(parts_for_vertex, part)

    # for part in range(parts_used):
    #     if bitset_in(parts_for_vertex, part):
    #         for other_part in range(part):
    #             if bitset_in(parts_for_vertex, other_part):
    #                 if bitset_issubset(
    #                     ctx.part_suffix_neighbors.rows[part],
    #                     ctx.part_suffix_neighbors.rows[other_part]
    #                 ):
    #                     bitset_discard(parts_for_vertex, part)
    #                     break
    #                 elif bitset_issubset(
    #                     ctx.part_suffix_neighbors.rows[other_part],
    #                     ctx.part_suffix_neighbors.rows[part]
    #                 ):
    #                     bitset_discard(parts_for_vertex, other_part)

    bitset_difference(parts_for_vertex, parts_for_vertex, ctx.forbidden_parts_for_vertices.rows[vertex])

    return parts_for_vertex


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

    _undo_update_forbidden_parts_for_vertices(ctx, vertex, suffix_vertices)

    return solution


cdef inline void _increment_prefix_greedily_on_existing_parts(
    _Context ctx,
    bitset_t suffix_vertices,
    int parts_used,
):
    """Add to prefix all vertices that have the same suffix neighbors as one of the parts."""
    cdef int level = _get_level(suffix_vertices)
    cdef int vertex
    cdef int part
    cdef bint suffix_changed = True
    while suffix_changed:
        suffix_changed = False
        vertex = bitset_next(suffix_vertices, 0)
        while vertex != -1:
            bitset_discard(suffix_vertices, vertex)

            part = _find_greedy_part_for_vertex(ctx, vertex, suffix_vertices, parts_used)

            if part != -1:
                ctx.prefix[level] = vertex
                ctx.part_of[vertex] = part
                level += 1
                suffix_changed = True
            else:
                bitset_add(suffix_vertices, vertex)

            vertex = bitset_next(suffix_vertices, vertex + 1)


cdef inline bint _add_vertex_to_prefix_greedily_on_part(
    _Context ctx,
    int part,
    bitset_t suffix_vertices,
):
    cdef int level = _get_level(suffix_vertices)
    cdef bint can_be_added
    cdef int vertex = bitset_next(suffix_vertices, 0)
    while vertex != -1:
        bitset_discard(suffix_vertices, vertex)

        bitset_intersection(
            ctx.suffix_neighbors_of_vertex,
            ctx.graph.rows[vertex],
            suffix_vertices
        )
        can_be_added = _is_greedy_part_for_vertex(ctx, part, suffix_vertices)

        if can_be_added:
            ctx.prefix[level] = vertex
            ctx.part_of[vertex] = part
            return True

        bitset_add(suffix_vertices, vertex)
        vertex = bitset_next(suffix_vertices, vertex + 1)

    return False


cdef inline int _find_greedy_part_for_vertex(
    _Context ctx,
    int vertex,
    bitset_t suffix_vertices,
    int parts_used,
):
    bitset_intersection(
        ctx.suffix_neighbors_of_vertex,
        ctx.graph.rows[vertex],
        suffix_vertices
    )
    for part in range(parts_used):
        if _is_greedy_part_for_vertex(ctx, part, suffix_vertices):
            return part
    return -1


cdef inline bint _is_greedy_part_for_vertex(
    _Context ctx,
    int part,
    bitset_t suffix_vertices,
):
    bitset_intersection(
        ctx.part_suffix_neighbors.rows[part],
        ctx.part_neighbors.rows[part],
        suffix_vertices
    )
    return bitset_eq(ctx.part_suffix_neighbors.rows[part], ctx.suffix_neighbors_of_vertex)


cdef inline bint _check_state_seen(
    _Context ctx,
    bitset_t suffix_vertices,
    int parts_used,
):
    bitset_complement(ctx.prefix_vertices, suffix_vertices)
    cdef int prefix_len = bitset_len(ctx.prefix_vertices)
    if prefix_len > ctx.max_prefix_length:
        return False

    cdef frozenset frozen_prefix_vertices = frozenset(bitset_list(ctx.prefix_vertices))
    frozen_part_neighbors = _build_frozen_part_neighbors(ctx, suffix_vertices, parts_used)
    cdef set seen_part_neighbors
    if frozen_prefix_vertices in ctx.seen_states:
        seen_part_neighbors = ctx.seen_states[frozen_prefix_vertices]
        if frozen_part_neighbors in seen_part_neighbors:
            return True
        elif ctx.seen_entries < ctx.max_seen_entries:
            seen_part_neighbors.add(frozen_part_neighbors)
            ctx.seen_entries += 1
    elif ctx.seen_entries < ctx.max_seen_entries:
        ctx.seen_states[frozen_prefix_vertices] = {frozen_part_neighbors}
        ctx.seen_entries += 1

    return False


cdef inline _build_frozen_part_neighbors(
    _Context ctx,
    bitset_t suffix_vertices,
    int parts_used,
):
    suffix_part_neighbors = Multiset()
    cdef frozenset part_suffix_neighbors_set
    for part in range(parts_used):
        bitset_intersection(
            ctx.part_suffix_neighbors.rows[part], ctx.part_neighbors.rows[part], suffix_vertices)
        part_suffix_neighbors_set = frozenset(bitset_list(ctx.part_suffix_neighbors.rows[part]))
        suffix_part_neighbors.add(part_suffix_neighbors_set)
    return FrozenMultiset(suffix_part_neighbors)


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


cdef inline void _update_forbidden_parts_for_vertices(
    _Context ctx,
    int new_vertex,
    int part_of_new_vertex,
    bitset_t suffix_vertices,
):
    # Uses ctx.suffix_neighbors_of_vertex as scratch for the suffix neighbors of
    # the prefix non neighbors of new_vertex.
    cdef bitset_s* neighbors_of_non_neighbors = &ctx.suffix_neighbors_of_vertex[0]
    bitset_complement(ctx.prefix_vertices, suffix_vertices)
    bitset_complement(ctx.prefix_non_neighbors_of_vertex, ctx.graph.rows[new_vertex])
    bitset_discard(ctx.prefix_non_neighbors_of_vertex, new_vertex)
    bitset_intersection(ctx.prefix_non_neighbors_of_vertex, ctx.prefix_non_neighbors_of_vertex, ctx.prefix_vertices)
    bitset_clear(neighbors_of_non_neighbors)
    for prefix_non_neighbor in bitset_list(ctx.prefix_non_neighbors_of_vertex):
        bitset_union(neighbors_of_non_neighbors, neighbors_of_non_neighbors, ctx.graph.rows[prefix_non_neighbor])

    bitset_intersection(neighbors_of_non_neighbors, neighbors_of_non_neighbors, suffix_vertices)

    for vertex in bitset_list(suffix_vertices):
        bitset_copy(
            ctx.previous_forbidden_parts_for_vertices[new_vertex].rows[vertex],
            ctx.forbidden_parts_for_vertices.rows[vertex]
        )

    for vertex in bitset_list(neighbors_of_non_neighbors):
        bitset_add(ctx.forbidden_parts_for_vertices.rows[vertex], part_of_new_vertex)


cdef inline void _undo_update_forbidden_parts_for_vertices(
    _Context ctx,
    int new_vertex,
    bitset_t suffix_vertices,
):
    for vertex in bitset_list(suffix_vertices):
        bitset_copy(
            ctx.forbidden_parts_for_vertices.rows[vertex],
            ctx.previous_forbidden_parts_for_vertices[new_vertex].rows[vertex]
        )

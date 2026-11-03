import itertools
from multiset import Multiset, FrozenMultiset

from sage.graphs.graph import Graph
from sage.data_structures.bitset import Bitset
from sage.data_structures.binary_matrix cimport *
from sage.graphs.base.static_dense_graph cimport dense_graph_init
from cysignals.memory cimport sig_malloc, sig_calloc, sig_free
from cysignals.signals cimport sig_on, sig_off 
from sage.graphs.graph_decompositions.vertex_separation import vertex_separation

from thinness.consistent_solution import ConsistentSolution 
from thinness.vertex_separation import solution_from_vertex_separation

DEFAULT_MAX_PREFIX_LENGTH = 15
DEFAULT_MAX_SEEN_ENTRIES = 1_000_000


def calculate_thinness(
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
        calculate_thinness_of_connected_graph(
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


def calculate_thinness_of_connected_graph(
    graph: Graph,
    lower_bound: int = 1,
    upper_bound: int = None,
    certificate: bool = False,
    max_prefix_length: int = DEFAULT_MAX_PREFIX_LENGTH,
    max_seen_entries: int = DEFAULT_MAX_SEEN_ENTRIES
) -> ConsistentSolution | int:
    """upper_bound is exclusive."""
    vertex_separation_value, vertex_separation_order = vertex_separation(graph)
    upper_bound_from_vertex_separation = max(vertex_separation_value, 1)
    if upper_bound_from_vertex_separation <= lower_bound:
        if certificate:
            return solution_from_vertex_separation(graph, vertex_separation_order)
        else:
            return upper_bound_from_vertex_separation
    upper_bound = (
        upper_bound_from_vertex_separation
        if upper_bound is None
        else min(upper_bound, upper_bound_from_vertex_separation)
    )

    cdef int max_branch_and_bound_thinness = upper_bound - 1

    cdef _Context ctx = _Context(
        graph,
        max_branch_and_bound_thinness,
        max_prefix_length,
        max_seen_entries
    )

    sig_on()
    branch_and_bound_thinness = _branch_and_bound(
        ctx,
        suffix_vertices=ctx.all_vertices,
        parts_used=0,
        lower_bound=lower_bound,
        upper_bound=max_branch_and_bound_thinness,
    )
    sig_off()

    cdef int thinness = branch_and_bound_thinness if branch_and_bound_thinness != -1 else upper_bound
    cdef list order
    cdef list partition
    if certificate:
        if branch_and_bound_thinness == -1:
            return solution_from_vertex_separation(graph, vertex_separation_order)
        order = [ctx.best_order[i] for i in range(ctx.n)]
        partition = [set() for _ in range(thinness)]
        for vertex in range(ctx.n):
            partition[ctx.best_partition[vertex]].add(vertex)
        return ConsistentSolution(order, partition)
    else:
        return thinness


cdef class _Context:
    """State shared by every call of the branch and bound recursion.

    Holds the graph, the scratch buffers and the search settings, so that the
    recursive functions only receive the values that change between calls.
    """
    cdef int n
    cdef binary_matrix_t graph
    cdef int* prefix
    cdef int* part_of
    cdef int* parts_rename
    cdef bitset_t all_vertices
    cdef bitset_t prefix_vertices
    cdef binary_matrix_t new_suffixes
    cdef binary_matrix_t part_neighbors
    cdef binary_matrix_t previous_part_neighbors
    cdef binary_matrix_t* parts_for_vertices
    cdef bitset_t suffix_neighbors_of_vertex
    cdef bitset_t suffix_neighbors_of_other_vertex
    cdef binary_matrix_t part_suffix_neighbors
    cdef binary_matrix_t vertices_not_added
    cdef bitset_t ignored_vertices
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
        int max_seen_entries
    ):
        dense_graph_init(self.graph, graph)

        cdef int n = self.graph.n_cols
        cdef int i
        self.n = n

        self.prefix = <int*>sig_malloc(sizeof(int) * n)
        self.part_of = <int*>sig_malloc(sizeof(int) * n)
        self.parts_rename = <int*>sig_malloc(sizeof(int) * max_parts)

        bitset_init(self.all_vertices, n)
        bitset_complement(self.all_vertices, self.all_vertices)

        bitset_init(self.prefix_vertices, n)
        binary_matrix_init(self.new_suffixes, n+1, n)
        binary_matrix_init(self.part_neighbors, max_parts, n)
        binary_matrix_init(self.previous_part_neighbors, n, n)

        # Zeroed so that __dealloc__ can free it even if an init below fails.
        self.parts_for_vertices = <binary_matrix_t*>sig_calloc(n, sizeof(binary_matrix_t))
        for i in range(n):
            binary_matrix_init(self.parts_for_vertices[i], n, max_parts)

        bitset_init(self.suffix_neighbors_of_vertex, n)
        bitset_init(self.suffix_neighbors_of_other_vertex, n)
        binary_matrix_init(self.part_suffix_neighbors, max_parts, n)
        binary_matrix_init(self.vertices_not_added, n, n)
        bitset_init(self.ignored_vertices, n)

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
        sig_free(self.parts_rename)
        bitset_free(self.all_vertices)
        bitset_free(self.prefix_vertices)
        binary_matrix_free(self.new_suffixes)
        binary_matrix_free(self.part_neighbors)
        binary_matrix_free(self.previous_part_neighbors)
        if self.parts_for_vertices != NULL:
            for i in range(self.n):
                binary_matrix_free(self.parts_for_vertices[i])
            sig_free(self.parts_for_vertices)
        bitset_free(self.suffix_neighbors_of_vertex)
        bitset_free(self.suffix_neighbors_of_other_vertex)
        binary_matrix_free(self.part_suffix_neighbors)
        binary_matrix_free(self.vertices_not_added)
        bitset_free(self.ignored_vertices)
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

    _increment_prefix_greedily_on_existing_parts(ctx, new_suffix, parts_used)

    if bitset_isempty(new_suffix) and parts_used <= upper_bound:
        _copy_array(ctx.n, ctx.prefix, ctx.best_order)
        _copy_array(ctx.n, ctx.part_of, ctx.best_partition)
        return parts_used

    if _check_state_seen(ctx, new_suffix, parts_used):
        return -1

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
        vertex_added_on_new_part = _add_vertex_to_prefix_greedily_on_part(ctx, part, new_suffix)

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
    cdef bitset_t my_vertices_not_added = ctx.vertices_not_added.rows[level]
    bitset_clear(my_vertices_not_added)
    cdef int best_solution_found = -1
    cdef bitset_t parts_for_vertex
    cdef int part
    cdef int vertex

    bitset_clear(ctx.ignored_vertices)
    vertex = bitset_next(suffix_vertices, 0)
    while vertex != -1:
        bitset_discard(suffix_vertices, vertex)
        parts_for_vertex = ctx.parts_for_vertices[level].rows[vertex]
        if _can_other_vertex_be_prepended_greedily(ctx, vertex, suffix_vertices, parts_used):
            # Not branched on, neither on an existing part nor on a new one.
            bitset_add(ctx.ignored_vertices, vertex)
            bitset_clear(parts_for_vertex)
        else:
            _get_available_parts_for_vertex(
                ctx,
                vertex,
                parts_used,
                parts_for_vertex,
                suffix_vertices,
            )
            if bitset_isempty(parts_for_vertex):
                bitset_add(my_vertices_not_added, vertex)
        bitset_add(suffix_vertices, vertex)
        vertex = bitset_next(suffix_vertices, vertex + 1)

    vertex = bitset_next(suffix_vertices, 0)
    while vertex != -1:
        bitset_discard(suffix_vertices, vertex)
        ctx.prefix[level] = vertex

        parts_for_vertex = ctx.parts_for_vertices[level].rows[vertex]
        part = bitset_next(parts_for_vertex, 0)
        while part != -1:
            if _can_other_vertex_be_prepended_freely(
                ctx,
                vertex,
                part,
                ctx.parts_for_vertices[level],
                suffix_vertices,
            ):
                part = bitset_next(parts_for_vertex, part + 1)
                continue

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


cdef inline void _get_available_parts_for_vertex(
    _Context ctx,
    int vertex,
    int parts_used,
    bitset_s* parts_for_vertex,
    bitset_t suffix_vertices,
):
    bitset_intersection(ctx.suffix_neighbors_of_vertex, ctx.graph.rows[vertex], suffix_vertices)

    bitset_clear(parts_for_vertex)
    for part in range(parts_used):
        bitset_intersection(
            ctx.part_suffix_neighbors.rows[part],
            ctx.part_neighbors.rows[part],
            suffix_vertices
        )
        if bitset_issubset(ctx.part_suffix_neighbors.rows[part], ctx.suffix_neighbors_of_vertex):
            bitset_add(parts_for_vertex, part)

    for part in range(parts_used):
        if bitset_in(parts_for_vertex, part):
            for other_part in range(part):
                if bitset_in(parts_for_vertex, other_part):
                    if bitset_issubset(
                        ctx.part_suffix_neighbors.rows[part],
                        ctx.part_suffix_neighbors.rows[other_part]
                    ):
                        bitset_discard(parts_for_vertex, part)
                        break
                    elif bitset_issubset(
                        ctx.part_suffix_neighbors.rows[other_part],
                        ctx.part_suffix_neighbors.rows[part]
                    ):
                        bitset_discard(parts_for_vertex, other_part)


cdef inline int _can_other_vertex_be_prepended_freely(
    _Context ctx,
    int vertex,
    int part,
    binary_matrix_t parts_for_vertices,
    bitset_t suffix_vertices,
):
    """`vertex` is not in suffix."""
    bitset_intersection(ctx.suffix_neighbors_of_vertex, ctx.graph.rows[vertex], suffix_vertices)
    cdef int other_vertex = bitset_next(suffix_vertices, 0)
    while other_vertex != -1:
        if bitset_in(parts_for_vertices.rows[other_vertex], part):
            bitset_intersection(
                ctx.suffix_neighbors_of_other_vertex,
                ctx.graph.rows[other_vertex],
                suffix_vertices
            )
            if bitset_issubset(ctx.suffix_neighbors_of_other_vertex, ctx.suffix_neighbors_of_vertex):
                bitset_discard(parts_for_vertices.rows[vertex], part)
                return True
        other_vertex = bitset_next(suffix_vertices, other_vertex + 1)
    return False


cdef inline bint _can_other_vertex_be_prepended_greedily(
    _Context ctx,
    int vertex,
    bitset_t suffix_vertices,
    int parts_used,
):
    """`vertex` is not in suffix.

    Whether there is a neighbor of `vertex` in the suffix that can be added to
    some part so that the part's suffix neighbors only gain `vertex`. In that
    case putting that neighbor and then `vertex` is always preferable to putting
    `vertex` next. This is the same as the neighbor having the same suffix
    neighbors as the part once `vertex` is removed from the suffix.

    Vertices in `ctx.ignored_vertices` are not considered as the neighbor, so
    that two vertices can't cause each other to be ignored.
    """
    cdef bint is_greedy
    cdef int other_vertex = bitset_next(suffix_vertices, 0)
    while other_vertex != -1:
        if (
            bitset_in(ctx.graph.rows[vertex], other_vertex)
            and not bitset_in(ctx.ignored_vertices, other_vertex)
        ):
            bitset_discard(suffix_vertices, other_vertex)
            is_greedy = _find_greedy_part_for_vertex(
                ctx, other_vertex, suffix_vertices, parts_used) != -1
            bitset_add(suffix_vertices, other_vertex)
            if is_greedy:
                return True
        other_vertex = bitset_next(suffix_vertices, other_vertex + 1)
    return False


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
    # Vertices discarded by _can_other_vertex_open_new_part_freely are removed from here.
    cdef bitset_t candidates = ctx.vertices_not_added.rows[level]
    if level == 0:
        bitset_copy(candidates, ctx.canonical_vertices)
    cdef int vertex = bitset_next(candidates, 0)
    while vertex != -1:
        bitset_discard(suffix_vertices, vertex)

        if not _can_other_vertex_open_new_part_freely(ctx, vertex, candidates, suffix_vertices):
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
        vertex = bitset_next(candidates, vertex + 1)

    return best_solution_found


cdef inline bint _can_other_vertex_open_new_part_freely(
    _Context ctx,
    int vertex,
    bitset_t candidates,
    bitset_t suffix_vertices,
):
    """`vertex` is not in suffix.

    If another candidate for the new part has its suffix neighbors contained in
    those of `vertex`, then `vertex` is discarded from `candidates`. Only vertices
    still in `candidates` are considered, so that a vertex that was already
    discarded can't cause another one to be discarded.
    """
    bitset_intersection(ctx.suffix_neighbors_of_vertex, ctx.graph.rows[vertex], suffix_vertices)
    cdef int other_vertex = bitset_next(candidates, 0)
    while other_vertex != -1:
        if other_vertex != vertex:
            bitset_intersection(
                ctx.suffix_neighbors_of_other_vertex,
                ctx.graph.rows[other_vertex],
                suffix_vertices
            )
            if bitset_issubset(ctx.suffix_neighbors_of_other_vertex, ctx.suffix_neighbors_of_vertex):
                bitset_discard(candidates, vertex)
                return True
        other_vertex = bitset_next(candidates, other_vertex + 1)
    return False


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

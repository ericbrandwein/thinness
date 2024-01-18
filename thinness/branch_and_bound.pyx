import itertools

from sage.graphs.graph import Graph
from sage.data_structures.bitset import Bitset
from sage.data_structures.binary_matrix cimport *
from sage.graphs.base.static_dense_graph cimport dense_graph_init
from cysignals.memory cimport check_malloc, sig_malloc, sig_free
from cysignals.signals cimport sig_on, sig_off 
from sage.graphs.graph_decompositions.vertex_separation import vertex_separation

from thinness.consistent_solution import ConsistentSolution 
from thinness.vertex_separation import solution_from_vertex_separation

DEFAULT_MAX_PREFIX_LENGTH = 15
DEFAULT_MAX_SEEN_ENTRIES = 1_000_000


def calculate_thinness_with_branch_and_bound(
    graph: Graph, 
    lower_bound: int = 1, 
    upper_bound: int = None,
    certificate: bool = False, 
    max_prefix_length: int = DEFAULT_MAX_PREFIX_LENGTH, 
    max_seen_entries: int = DEFAULT_MAX_SEEN_ENTRIES
) -> ConsistentSolution | int:
    components = [graph.subgraph(component, immutable=False) for component in graph.connected_components()]
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


def _join_solutions(solutions: list[ConsistentSolution], relabellings: list[dict[int, int]]) -> ConsistentSolution:
    order = _join_orders([solution.order for solution in solutions], relabellings)
    partition = _join_partitions([solution.partition for solution in solutions], relabellings)
    return ConsistentSolution(order, partition)


def _join_orders(orders: list[list[int]], relabellings: list[dict[int, int]]) -> list[int]:
    orders = [
        [_original_label(vertex, relabellings[i]) for vertex in order]
        for i, order in enumerate(orders)
    ]
    return list(itertools.chain.from_iterable(orders))


def _join_partitions(partitions: list[list[set]], relabellings: list[dict[int, int]]) -> list[set]:
    partitions = [
        [set(_original_label(vertex, relabellings[i]) for vertex in part) for part in partition]
        for i, partition in enumerate(partitions)
    ]
    return [
        set(itertools.chain.from_iterable(parts))
        for parts in itertools.zip_longest(*partitions, fillvalue=set())
    ]


def _original_label(vertex: int, relabelling: dict[int, int]) -> int:
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

    cdef binary_matrix_t adjacency_matrix
    dense_graph_init(adjacency_matrix, graph)

    cdef int n = adjacency_matrix.n_cols

    cdef bitset_t prefix_vertices
    bitset_init(prefix_vertices, n)

    cdef bitset_t suffix_vertices
    bitset_init(suffix_vertices, n)
    bitset_complement(suffix_vertices, suffix_vertices)

    cdef binary_matrix_t new_suffixes
    binary_matrix_init(new_suffixes, n+1, n)
    
    cdef int* prefix = <int*>sig_malloc(sizeof(int) * n)
    cdef int* part_of = <int*>sig_malloc(sizeof(int) * n)
    cdef int* parts_rename = <int*>sig_malloc(sizeof(int) * max_branch_and_bound_thinness)

    cdef binary_matrix_t part_neighbors
    binary_matrix_init(part_neighbors, max_branch_and_bound_thinness, n)

    cdef binary_matrix_t previous_part_neighbors
    binary_matrix_init(previous_part_neighbors, n, n)

    cdef binary_matrix_t parts_for_vertices
    binary_matrix_init(parts_for_vertices, n, max_branch_and_bound_thinness)
    
    cdef bitset_t suffix_neighbors_of_vertex
    bitset_init(suffix_neighbors_of_vertex, n)

    cdef binary_matrix_t part_suffix_neighbors
    binary_matrix_init(part_suffix_neighbors, max_branch_and_bound_thinness, n)
    
    cdef bitset_t vertices_not_added
    bitset_init(vertices_not_added, n)
    
    cdef dict seen_states = dict() 

    cdef int seen_entries = 0

    cdef int* best_order = <int*>sig_malloc(sizeof(int) * n)
    cdef int* best_partition = <int*>sig_malloc(sizeof(int) * n)

    cdef bitset_t canonical_vertices
    bitset_init(canonical_vertices, n)
    _build_canonical_vertices(graph, canonical_vertices)

    try:
        sig_on()
        branch_and_bound_thinness = _branch_and_bound(
            graph=adjacency_matrix,
            prefix=prefix,
            part_of=part_of,
            parts_rename=parts_rename,
            parts_used=0,
            prefix_vertices=prefix_vertices,
            suffix_vertices=suffix_vertices,
            new_suffixes=new_suffixes,
            part_neighbors=part_neighbors,
            previous_part_neighbors=previous_part_neighbors,
            parts_for_vertices=parts_for_vertices,
            suffix_neighbors_of_vertex=suffix_neighbors_of_vertex,
            part_suffix_neighbors=part_suffix_neighbors,
            vertices_not_added=vertices_not_added,
            seen_states=seen_states,
            seen_entries=&seen_entries,
            canonical_vertices=canonical_vertices,
            lower_bound=lower_bound,
            upper_bound=max_branch_and_bound_thinness,
            best_order=best_order,
            best_partition=best_partition,
            max_prefix_length=max_prefix_length,
            max_seen_entries=max_seen_entries,
        )
        sig_off()
    finally:
        binary_matrix_free(adjacency_matrix)
        bitset_free(prefix_vertices)
        bitset_free(suffix_vertices)
        binary_matrix_free(new_suffixes)
        sig_free(prefix)
        sig_free(part_of)
        sig_free(parts_rename)
        binary_matrix_free(part_neighbors)
        binary_matrix_free(previous_part_neighbors)
        binary_matrix_free(parts_for_vertices)
        bitset_free(suffix_neighbors_of_vertex)
        binary_matrix_free(part_suffix_neighbors)
        bitset_free(canonical_vertices)

    cdef int thinness = branch_and_bound_thinness if branch_and_bound_thinness != -1 else upper_bound
    cdef list order
    cdef list partition
    if certificate:
        if branch_and_bound_thinness == -1:
            ret = solution_from_vertex_separation(graph, vertex_separation_order)
        else:    
            order = [best_order[i] for i in range(n)]
            partition = [set() for _ in range(thinness)]
            for vertex in range(n):
                partition[best_partition[vertex]].add(vertex)
            ret = ConsistentSolution(order, partition)
    else:
        ret = thinness

    sig_free(best_order)
    sig_free(best_partition)

    return ret


cdef inline void _build_canonical_vertices(graph: Graph, bitset_t canonical_vertices):
    cdef list orbit
    for orbit in graph.automorphism_group(orbits=True, return_group=False):
        bitset_add(canonical_vertices, <int> orbit[0])


cdef int _branch_and_bound(
    binary_matrix_t graph,
    int* prefix,
    int* part_of,
    int* parts_rename,
    int parts_used,
    bitset_t prefix_vertices,
    bitset_t suffix_vertices,
    binary_matrix_t new_suffixes,
    binary_matrix_t part_neighbors,
    binary_matrix_t previous_part_neighbors,
    binary_matrix_t parts_for_vertices,
    bitset_t suffix_neighbors_of_vertex,
    binary_matrix_t part_suffix_neighbors,
    bitset_t vertices_not_added,
    dict seen_states,
    int* seen_entries,
    bitset_t canonical_vertices,
    int lower_bound,
    int upper_bound,
    int* best_order,
    int* best_partition,
    int max_prefix_length,
    int max_seen_entries,
):
    cdef int level = _get_level(suffix_vertices)
  
    cdef bitset_t new_suffix = new_suffixes.rows[level]
    bitset_copy(new_suffix, suffix_vertices)

    _increment_prefix_greedily_on_existing_parts(
        graph,
        new_suffix,
        parts_used,
        prefix,
        part_of,
        part_neighbors,
        suffix_neighbors_of_vertex,
        part_suffix_neighbors
    )

    if bitset_isempty(new_suffix) and parts_used <= upper_bound:
        _copy_array(graph.n_cols, prefix, best_order)
        _copy_array(graph.n_cols, part_of, best_partition)
        return parts_used

    if _check_state_seen(
        seen_states,
        seen_entries,
        prefix_vertices,
        new_suffix,
        parts_used,
        part_neighbors,
        part_suffix_neighbors,
        max_prefix_length,
        max_seen_entries
    ):
        return -1
    
    cdef int best_solution_found = _branch_adding_to_existing_part(
        graph,
        prefix,
        part_of,
        parts_rename,
        parts_used,
        prefix_vertices,
        new_suffix,
        new_suffixes,
        part_neighbors,
        previous_part_neighbors,
        parts_for_vertices,
        suffix_neighbors_of_vertex,
        part_suffix_neighbors,
        vertices_not_added,
        seen_states,
        seen_entries,
        canonical_vertices,
        lower_bound,
        upper_bound,
        best_order,
        best_partition,
        max_prefix_length,
        max_seen_entries,
    )
    
    cdef int new_part_solution
    cdef int part
    cdef int vertex_added_on_new_part
    if parts_used < upper_bound:
        parts_used += 1
        part = parts_used - 1
        lower_bound = max(lower_bound, parts_used)
        vertex_added_on_new_part = _add_vertex_to_prefix_greedily_on_part(
            part,
            graph,
            prefix_vertices,
            new_suffix,
            suffix_neighbors_of_vertex,
            part_suffix_neighbors,
            prefix,
            part_of,
            part_neighbors,
        )
        
        if vertex_added_on_new_part:
            new_part_solution = _branch_and_bound(
                graph,
                prefix,
                part_of,
                parts_rename,
                parts_used,
                prefix_vertices,
                new_suffix,
                new_suffixes,
                part_neighbors,
                previous_part_neighbors,
                parts_for_vertices,
                suffix_neighbors_of_vertex,
                part_suffix_neighbors,
                vertices_not_added,
                seen_states,
                seen_entries,
                canonical_vertices,
                lower_bound,
                upper_bound,
                best_order,
                best_partition,
                max_prefix_length,
                max_seen_entries,
            )
        else:
            new_part_solution = _branch_adding_to_new_part(
                graph,
                prefix,
                part_of,
                parts_rename,
                parts_used,
                prefix_vertices,
                new_suffix,
                new_suffixes,
                part_neighbors,
                previous_part_neighbors,
                parts_for_vertices,
                suffix_neighbors_of_vertex,
                part_suffix_neighbors,
                vertices_not_added,
                seen_states,
                seen_entries,
                canonical_vertices,
                lower_bound,
                upper_bound,
                best_order,
                best_partition,
                max_prefix_length,
                max_seen_entries,
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
    binary_matrix_t graph,
    int* prefix,
    int* part_of,
    int* parts_rename,
    int parts_used,
    bitset_t prefix_vertices,
    bitset_t suffix_vertices,
    binary_matrix_t new_suffixes,
    binary_matrix_t part_neighbors,
    binary_matrix_t previous_part_neighbors,
    binary_matrix_t parts_for_vertices,
    bitset_t suffix_neighbors_of_vertex,
    binary_matrix_t part_suffix_neighbors,
    bitset_t vertices_not_added,
    dict seen_states,
    int* seen_entries,
    bitset_t canonical_vertices,
    int lower_bound,
    int upper_bound,
    int* best_order,
    int* best_partition,
    int max_prefix_length,
    int max_seen_entries,
):
    cdef int level = _get_level(suffix_vertices)
    cdef int best_solution_found = -1
    cdef bitset_t parts_for_vertex
    cdef int part
    bitset_clear(vertices_not_added)
    cdef int vertex = bitset_next(suffix_vertices, 0)
    while vertex != -1:
        bitset_discard(suffix_vertices, vertex)
        prefix[level] = vertex

        parts_for_vertex = _get_available_parts_for_vertex(
            vertex, 
            parts_used,
            parts_for_vertices,
            part_neighbors,
            suffix_vertices,
            graph.rows[vertex],
            suffix_neighbors_of_vertex,
            part_suffix_neighbors
        )

        if bitset_isempty(parts_for_vertex):
            bitset_add(vertices_not_added, vertex)
        part = bitset_next(parts_for_vertex, 0)
        while part != -1:
            current_solution = _branch_with_vertex_on_part(
                vertex,
                part,
                graph,
                prefix,
                part_of,
                parts_rename,
                parts_used,
                prefix_vertices,
                suffix_vertices,
                new_suffixes,
                part_neighbors,
                previous_part_neighbors,
                parts_for_vertices,
                suffix_neighbors_of_vertex,
                part_suffix_neighbors,
                vertices_not_added,
                seen_states,
                seen_entries,
                canonical_vertices,
                lower_bound,
                upper_bound,
                best_order,
                best_partition,
                max_prefix_length,
                max_seen_entries,
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
    int vertex, 
    int parts_used,
    binary_matrix_t parts_for_vertices,
    binary_matrix_t part_neighbors,
    bitset_t suffix_vertices,
    bitset_t neighbors_of_vertex,
    bitset_t suffix_neighbors_of_vertex,
    binary_matrix_t part_suffix_neighbors
):
    bitset_intersection(suffix_neighbors_of_vertex, neighbors_of_vertex, suffix_vertices)
    
    cdef bitset_s* parts_for_vertex = parts_for_vertices.rows[vertex]
    bitset_clear(parts_for_vertex)
    for part in range(parts_used):
        bitset_intersection(
            part_suffix_neighbors.rows[part],
            part_neighbors.rows[part],
            suffix_vertices
        )
        if bitset_issubset(part_suffix_neighbors.rows[part], suffix_neighbors_of_vertex):
            bitset_add(parts_for_vertex, part)

    for part in range(parts_used):
        if bitset_in(parts_for_vertex, part):
            for other_part in range(part):
                if bitset_in(parts_for_vertex, other_part):
                    if bitset_issubset(
                        part_suffix_neighbors.rows[part],
                        part_suffix_neighbors.rows[other_part]
                    ):
                        bitset_discard(parts_for_vertex, part)
                        break
                    elif bitset_issubset(
                        part_suffix_neighbors.rows[other_part],
                        part_suffix_neighbors.rows[part]
                    ):
                        bitset_discard(parts_for_vertex, other_part)
    
    return parts_for_vertex


cdef inline int _branch_adding_to_new_part(
    binary_matrix_t graph,
    int* prefix,
    int* part_of,
    int* parts_rename,
    int parts_used,
    bitset_t prefix_vertices,
    bitset_t suffix_vertices,
    binary_matrix_t new_suffixes,
    binary_matrix_t part_neighbors,
    binary_matrix_t previous_part_neighbors,
    binary_matrix_t parts_for_vertices,
    bitset_t suffix_neighbors_of_vertex,
    binary_matrix_t part_suffix_neighbors,
    bitset_t vertices_not_added,
    dict seen_states,
    int* seen_entries,
    bitset_t canonical_vertices,
    int lower_bound,
    int upper_bound,
    int* best_order,
    int* best_partition,
    int max_prefix_length,
    int max_seen_entries,
):
    cdef int level = _get_level(suffix_vertices)
    cdef int best_solution_found = -1
    cdef int part = parts_used - 1
    cdef bitset_t vertices = canonical_vertices if level == 0 else vertices_not_added
    cdef int vertex = bitset_next(vertices, 0)
    while vertex != -1:
        bitset_discard(suffix_vertices, vertex)
        prefix[level] = vertex

        current_solution = _branch_with_vertex_on_part(
            vertex,
            part,
            graph,
            prefix,
            part_of,
            parts_rename,
            parts_used,
            prefix_vertices,
            suffix_vertices,
            new_suffixes,
            part_neighbors,
            previous_part_neighbors,
            parts_for_vertices,
            suffix_neighbors_of_vertex,
            part_suffix_neighbors,
            vertices_not_added,
            seen_states,
            seen_entries,
            canonical_vertices,
            lower_bound,
            upper_bound,
            best_order,
            best_partition,
            max_prefix_length,
            max_seen_entries,
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
    int vertex,
    int part,
    binary_matrix_t graph,
    int* prefix,
    int* part_of,
    int* parts_rename,
    int parts_used,
    bitset_t prefix_vertices,
    bitset_t suffix_vertices,
    binary_matrix_t new_suffixes,
    binary_matrix_t part_neighbors,
    binary_matrix_t previous_part_neighbors,
    binary_matrix_t parts_for_vertices,
    bitset_t suffix_neighbors_of_vertex,
    binary_matrix_t part_suffix_neighbors,
    bitset_t vertices_not_added,
    dict seen_states,
    int* seen_entries,
    bitset_t canonical_vertices,
    int lower_bound,
    int upper_bound,
    int* best_order,
    int* best_partition,
    int max_prefix_length,
    int max_seen_entries,
):
    part_of[vertex] = part

    _update_part_neighbors(
        part_neighbors.rows[part],
        previous_part_neighbors.rows[vertex],
        graph.rows[vertex]
    )

    cdef int solution = _branch_and_bound(
        graph,
        prefix,
        part_of,
        parts_rename,
        parts_used,
        prefix_vertices,
        suffix_vertices,
        new_suffixes,
        part_neighbors,
        previous_part_neighbors,
        parts_for_vertices,
        suffix_neighbors_of_vertex,
        part_suffix_neighbors,
        vertices_not_added,
        seen_states,
        seen_entries,
        canonical_vertices,
        lower_bound,
        upper_bound,
        best_order,
        best_partition,
        max_prefix_length,
        max_seen_entries,
    )

    _undo_update_part_neighbors(
        part_neighbors.rows[part],
        previous_part_neighbors.rows[vertex]
    )

    return solution


cdef inline void _increment_prefix_greedily_on_existing_parts(
    binary_matrix_t graph,
    bitset_t suffix_vertices,
    int parts_used,
    int* prefix,
    int* part_of,
    binary_matrix_t part_neighbors,
    bitset_t suffix_neighbors_of_vertex,
    binary_matrix_t part_suffix_neighbors,
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

            part = _find_greedy_part_for_vertex(
                vertex,
                graph,
                suffix_vertices,
                parts_used,
                part_neighbors,
                suffix_neighbors_of_vertex,
                part_suffix_neighbors,
            )

            if part != -1:
                prefix[level] = vertex
                part_of[vertex] = part
                level += 1
                suffix_changed = True
            else:
                bitset_add(suffix_vertices, vertex)

            vertex = bitset_next(suffix_vertices, vertex + 1)


cdef inline bint _add_vertex_to_prefix_greedily_on_part(
    int part,
    binary_matrix_t graph,
    bitset_t prefix_vertices,
    bitset_t suffix_vertices,
    bitset_t suffix_neighbors_of_vertex,
    binary_matrix_t part_suffix_neighbors,
    int* prefix,
    int* part_of,
    binary_matrix_t part_neighbors,
):
    cdef int level = _get_level(suffix_vertices)
    cdef bint can_be_added
    cdef int vertex = bitset_next(suffix_vertices, 0)
    while vertex != -1:
        bitset_discard(suffix_vertices, vertex)

        bitset_intersection(
            suffix_neighbors_of_vertex, 
            graph.rows[vertex], 
            suffix_vertices
        )
        can_be_added = _is_greedy_part_for_vertex(
            part,
            suffix_vertices,
            part_neighbors,
            suffix_neighbors_of_vertex,
            part_suffix_neighbors,
        )

        if can_be_added:
            prefix[level] = vertex
            part_of[vertex] = part
            return True

        bitset_add(suffix_vertices, vertex)
        vertex = bitset_next(suffix_vertices, vertex + 1)
    
    return False 


cdef inline int _find_greedy_part_for_vertex(
    int vertex,
    binary_matrix_t graph,
    bitset_t suffix_vertices,
    int parts_used,
    binary_matrix_t part_neighbors,
    bitset_t suffix_neighbors_of_vertex,
    binary_matrix_t part_suffix_neighbors,
):
    bitset_intersection(
        suffix_neighbors_of_vertex, 
        graph.rows[vertex], 
        suffix_vertices
    )
    for part in range(parts_used):
        if _is_greedy_part_for_vertex(
            part,
            suffix_vertices,
            part_neighbors,
            suffix_neighbors_of_vertex,
            part_suffix_neighbors,
        ):
            return part
    return -1


cdef inline bint _is_greedy_part_for_vertex(
    int part,
    bitset_t suffix_vertices,
    binary_matrix_t part_neighbors,
    bitset_t suffix_neighbors_of_vertex,
    binary_matrix_t part_suffix_neighbors,
):
    bitset_intersection(
        part_suffix_neighbors.rows[part],
        part_neighbors.rows[part],
        suffix_vertices
    )
    return bitset_eq(part_suffix_neighbors.rows[part], suffix_neighbors_of_vertex)


cdef inline bint _check_state_seen(
    dict seen_states,
    int* seen_entries,
    bitset_t prefix_vertices,
    bitset_t suffix_vertices,
    int parts_used,
    binary_matrix_t part_neighbors,
    binary_matrix_t part_suffix_neighbors,
    int max_prefix_length,
    int max_seen_entries
):
    bitset_complement(prefix_vertices, suffix_vertices)
    cdef int prefix_len = bitset_len(prefix_vertices)
    if prefix_len > max_prefix_length:
        return False

    cdef frozenset frozen_prefix_vertices = frozenset(bitset_list(prefix_vertices))
    cdef frozenset frozen_part_neighbors = _build_frozen_part_neighbors(
        suffix_vertices, parts_used, part_neighbors, part_suffix_neighbors)
    cdef dict seen_part_neighbors
    cdef int parts_used_before
    cdef bint state_seen = False
    if frozen_prefix_vertices in seen_states:
        seen_part_neighbors = seen_states[frozen_prefix_vertices]
        if frozen_part_neighbors in seen_part_neighbors:
            parts_used_before = seen_part_neighbors[frozen_part_neighbors]
            if parts_used_before <= parts_used:
                state_seen = True
            else:
                seen_part_neighbors[frozen_part_neighbors] = parts_used
        elif seen_entries[0] < max_seen_entries:
            seen_part_neighbors[frozen_part_neighbors] = parts_used
            seen_entries[0] += 1
    elif seen_entries[0] < max_seen_entries:
        seen_states[frozen_prefix_vertices] = {frozen_part_neighbors: parts_used}
        seen_entries[0] += 1
    
    return state_seen


cdef inline _build_frozen_part_neighbors(
    bitset_t suffix_vertices,
    int parts_used, 
    binary_matrix_t part_neighbors,
    binary_matrix_t part_suffix_neighbors
):
    cdef set suffix_part_neighbors = set()
    cdef frozenset part_suffix_neighbors_set 
    for part in range(parts_used):
        bitset_intersection(
            part_suffix_neighbors.rows[part], part_neighbors.rows[part], suffix_vertices)
        part_suffix_neighbors_set = frozenset(bitset_list(part_suffix_neighbors.rows[part]))
        suffix_part_neighbors.add(part_suffix_neighbors_set)
    return frozenset(suffix_part_neighbors)


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

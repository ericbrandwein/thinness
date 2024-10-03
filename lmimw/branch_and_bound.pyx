import itertools

from sage.graphs.graph import Graph
from sage.data_structures.bitset import Bitset
from sage.data_structures.binary_matrix cimport *
from sage.graphs.base.static_dense_graph cimport dense_graph_init
from sage.numerical.mip cimport MixedIntegerLinearProgram
from cysignals.memory cimport check_malloc, sig_malloc, sig_free
from cysignals.signals cimport sig_on, sig_off 

DEFAULT_MAX_PREFIX_LENGTH = 15
DEFAULT_MAX_SEEN_ENTRIES = 1_000_000


def lmimwidth(
    graph: Graph, 
    lower_bound: int = 0, 
    upper_bound: int = None,
    certificate: bool = False, 
    max_prefix_length: int = DEFAULT_MAX_PREFIX_LENGTH, 
    max_seen_entries: int = DEFAULT_MAX_SEEN_ENTRIES
) -> (int, list) | int:
    components = [graph.subgraph(component, immutable=False) for component in graph.connected_components()]
    relabellings = [component.relabel(return_map=True) for component in components]
    solutions = [
        lmimwidth_of_connected_graph(
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


def _join_solutions(solutions: list[tuple(int, list[int])], relabellings: list[dict]) -> tuple[int, list]:
    width = max(solution[0] for solution in solutions)
    orders = [
        [_original_label(vertex, relabellings[i]) for vertex in solution[1]]
        for i, solution in enumerate(solutions)
    ]
    order = list(itertools.chain.from_iterable(orders))
    return width, order


def _original_label(vertex: int, relabelling: dict):
    return next(key for key, value in relabelling.items() if value == vertex)


def lmimwidth_of_connected_graph(
    graph: Graph, 
    lower_bound: int = 0, 
    upper_bound: int = None,
    certificate: bool = False,
    max_prefix_length: int = DEFAULT_MAX_PREFIX_LENGTH, 
    max_seen_entries: int = DEFAULT_MAX_SEEN_ENTRIES
) -> (int, list[int]) | int:
    """upper_bound is exclusive."""

    cdef int max_branch_and_bound_lmimw = upper_bound - 1 if upper_bound is not None else graph.order() // 2

    cdef binary_matrix_t adjacency_matrix
    dense_graph_init(adjacency_matrix, graph)

    cdef int n = adjacency_matrix.n_cols

    cdef bitset_t suffix_vertices
    bitset_init(suffix_vertices, n)
    bitset_complement(suffix_vertices, suffix_vertices)

    cdef bitset_t prefix_vertices
    bitset_init(prefix_vertices, n)

    cdef int* prefix = <int*>sig_malloc(sizeof(int) * n)

    cdef bitset_t prefix_neighbors_of_vertex
    bitset_init(prefix_neighbors_of_vertex, n)

    cdef bitset_t suffix_neighbors_of_vertex
    bitset_init(suffix_neighbors_of_vertex, n)
    
    cdef dict seen_states = dict() 

    cdef int seen_entries = 0

    cdef int* best_order = <int*>sig_malloc(sizeof(int) * n)

    cdef bitset_t canonical_vertices
    bitset_init(canonical_vertices, n)
    _build_canonical_vertices(graph, canonical_vertices)

    try:
        sig_on()
        branch_and_bound_lmimw = _branch_and_bound(
            graph=adjacency_matrix,
            prefix=prefix,
            current_mim=0,
            prefix_vertices=prefix_vertices,
            suffix_vertices=suffix_vertices,
            prefix_neighbors_of_vertex=prefix_neighbors_of_vertex,
            suffix_neighbors_of_vertex=suffix_neighbors_of_vertex,
            seen_states=seen_states,
            seen_entries=&seen_entries,
            canonical_vertices=canonical_vertices,
            lower_bound=lower_bound,
            upper_bound=max_branch_and_bound_lmimw,
            best_order=best_order,
            max_prefix_length=max_prefix_length,
            max_seen_entries=max_seen_entries,
        )
        sig_off()
    finally:
        binary_matrix_free(adjacency_matrix)
        bitset_free(suffix_vertices)
        sig_free(prefix)
        bitset_free(suffix_neighbors_of_vertex)
        bitset_free(canonical_vertices)

    cdef int lmimw = branch_and_bound_lmimw if branch_and_bound_lmimw != -1 else upper_bound
    cdef list order
    if certificate:
        if branch_and_bound_lmimw == -1:
            ret = None
        else:    
            order = [best_order[i] for i in range(n)]
            ret = lmimw, order
    else:
        ret = lmimw

    sig_free(best_order)

    return ret


cdef inline void _build_canonical_vertices(graph: Graph, bitset_t canonical_vertices):
    cdef list orbit
    for orbit in graph.automorphism_group(orbits=True, return_group=False):
        bitset_add(canonical_vertices, <int> orbit[0])

"""
upper_bound is inclusive.
"""
cdef int _branch_and_bound(
    binary_matrix_t graph,
    int* prefix,
    int current_mim,
    bitset_t prefix_vertices,
    bitset_t suffix_vertices,
    bitset_t prefix_neighbors_of_vertex,
    bitset_t suffix_neighbors_of_vertex,
    dict seen_states,
    int* seen_entries,
    bitset_t canonical_vertices,
    int lower_bound,
    int upper_bound,
    int* best_order,
    int max_prefix_length,
    int max_seen_entries,
):
    cdef int level = _get_level(suffix_vertices)

    # If some vertex has no neighbors in the suffix, we could add it to the prefix.
    # _increment_prefix_greedily_on_existing_parts(
    #     graph,
    #     new_suffix,
    #     parts_used,
    #     prefix,
    #     part_of,
    #     part_neighbors,
    #     suffix_neighbors_of_vertex,
    #     part_suffix_neighbors
    # )

    if bitset_isempty(suffix_vertices) and current_mim <= upper_bound:
        _copy_array(graph.n_cols, prefix, best_order)
        return current_mim

    # If we already saw this prefix with same or better current_mim, skip this state.
    # if _check_state_seen(
    #     seen_states,
    #     seen_entries,
    #     prefix_vertices,
    #     new_suffix,
    #     parts_used,
    #     part_neighbors,
    #     part_suffix_neighbors,
    #     max_prefix_length,
    #     max_seen_entries
    # ):
    #     return -1
    
    # Add each possible vertex to the order and branch.

    cdef int best_solution_found = -1
    cdef int vertex = bitset_next(suffix_vertices, 0)
    while vertex != -1:
        bitset_discard(suffix_vertices, vertex)
        prefix[level] = vertex

        mim = _get_mim_for_cut(
            graph, 
            prefix, 
            prefix_vertices, 
            suffix_vertices, 
            prefix_neighbors_of_vertex, 
            suffix_neighbors_of_vertex
        )
        new_current_mim = max(current_mim, mim)
        current_solution = _branch_and_bound(
            graph,
            prefix,
            new_current_mim,
            prefix_vertices,
            suffix_vertices,
            prefix_neighbors_of_vertex,
            suffix_neighbors_of_vertex,
            seen_states,
            seen_entries,
            canonical_vertices,
            lower_bound,
            upper_bound,
            best_order,
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
        vertex = bitset_next(suffix_vertices, vertex + 1)
    
    return best_solution_found


cdef inline int _get_level(bitset_t suffix_vertices):
    return suffix_vertices.size - bitset_len(suffix_vertices)


cdef inline void _copy_array(int n, int* array_from, int* array_to):
    for i in range(n):
        array_to[i] = array_from[i]


cdef int _get_mim_for_cut(
    binary_matrix_t graph, 
    int* prefix,
    bitset_t prefix_vertices,
    bitset_t suffix_vertices,
    bitset_t prefix_neighbors_of_vertex,
    bitset_t suffix_neighbors_of_vertex
):
    cdef int size_of_prefix = _get_level(suffix_vertices)
    bitset_complement(prefix_vertices, suffix_vertices)
    cdef int prefix_vertex
    cdef int suffix_vertex
    cdef int neighbor_of_suffix_vertex
    
    mip = MixedIntegerLinearProgram()
    edge_variables = mip.new_variable(binary=True)

    for prefix_vertex_index in range(size_of_prefix):
        prefix_vertex = prefix[prefix_vertex_index]
        bitset_intersection(
            suffix_neighbors_of_vertex, 
            graph.rows[prefix_vertex], 
            suffix_vertices
        )
        suffix_vertex = bitset_next(suffix_neighbors_of_vertex, 0)
        if suffix_vertex != -1:
            edge_variables_sum = edge_variables[prefix_vertex, suffix_vertex]
            suffix_vertex = bitset_next(suffix_neighbors_of_vertex, suffix_vertex + 1)
            while suffix_vertex != -1:
                edge_variables_sum += edge_variables[prefix_vertex, suffix_vertex]
                suffix_vertex = bitset_next(suffix_neighbors_of_vertex, suffix_vertex + 1)
            
            suffix_vertex = bitset_next(suffix_neighbors_of_vertex, 0)
            while suffix_vertex != -1:
                edge_variables_sum_for_suffix_vertex = edge_variables_sum
                bitset_intersection(
                    prefix_neighbors_of_vertex,
                    graph.rows[suffix_vertex],
                    prefix_vertices
                )
                bitset_discard(prefix_neighbors_of_vertex, prefix_vertex)
                neighbor_of_suffix_vertex = bitset_next(prefix_neighbors_of_vertex, 0)
                while neighbor_of_suffix_vertex != -1:
                    edge_variables_sum_for_suffix_vertex += edge_variables[neighbor_of_suffix_vertex, suffix_vertex]
                    neighbor_of_suffix_vertex = bitset_next(
                        prefix_neighbors_of_vertex, 
                        neighbor_of_suffix_vertex + 1
                    )
                mip.add_constraint(edge_variables_sum_for_suffix_vertex <= 1)
                suffix_vertex = bitset_next(suffix_neighbors_of_vertex, suffix_vertex + 1)
    
    mip.set_objective(mip.sum(edge_variables.values()))
    return mip.solve()


# cdef inline void _increment_prefix_greedily_on_existing_parts(
#     binary_matrix_t graph,
#     bitset_t suffix_vertices,
#     int parts_used,
#     int* prefix,
#     int* part_of,
#     binary_matrix_t part_neighbors,
#     bitset_t suffix_neighbors_of_vertex,
#     binary_matrix_t part_suffix_neighbors,
# ):
#     """Add to prefix all vertices that have the same suffix neighbors as one of the parts."""
#     cdef int level = _get_level(suffix_vertices)
#     cdef int vertex
#     cdef int part
#     cdef bint suffix_changed = True
#     while suffix_changed:
#         suffix_changed = False
#         vertex = bitset_next(suffix_vertices, 0)
#         while vertex != -1:
#             bitset_discard(suffix_vertices, vertex)

#             part = _find_greedy_part_for_vertex(
#                 vertex,
#                 graph,
#                 suffix_vertices,
#                 parts_used,
#                 part_neighbors,
#                 suffix_neighbors_of_vertex,
#                 part_suffix_neighbors,
#             )

#             if part != -1:
#                 prefix[level] = vertex
#                 part_of[vertex] = part
#                 level += 1
#                 suffix_changed = True
#             else:
#                 bitset_add(suffix_vertices, vertex)

#             vertex = bitset_next(suffix_vertices, vertex + 1)


# cdef inline bint _add_vertex_to_prefix_greedily_on_part(
#     int part,
#     binary_matrix_t graph,
#     bitset_t prefix_vertices,
#     bitset_t suffix_vertices,
#     bitset_t suffix_neighbors_of_vertex,
#     binary_matrix_t part_suffix_neighbors,
#     int* prefix,
#     int* part_of,
#     binary_matrix_t part_neighbors,
# ):
#     cdef int level = _get_level(suffix_vertices)
#     cdef bint can_be_added
#     cdef int vertex = bitset_next(suffix_vertices, 0)
#     while vertex != -1:
#         bitset_discard(suffix_vertices, vertex)

#         bitset_intersection(
#             suffix_neighbors_of_vertex, 
#             graph.rows[vertex], 
#             suffix_vertices
#         )
#         can_be_added = _is_greedy_part_for_vertex(
#             part,
#             suffix_vertices,
#             part_neighbors,
#             suffix_neighbors_of_vertex,
#             part_suffix_neighbors,
#         )

#         if can_be_added:
#             prefix[level] = vertex
#             part_of[vertex] = part
#             return True

#         bitset_add(suffix_vertices, vertex)
#         vertex = bitset_next(suffix_vertices, vertex + 1)
    
#     return False 


# cdef inline int _find_greedy_part_for_vertex(
#     int vertex,
#     binary_matrix_t graph,
#     bitset_t suffix_vertices,
#     int parts_used,
#     binary_matrix_t part_neighbors,
#     bitset_t suffix_neighbors_of_vertex,
#     binary_matrix_t part_suffix_neighbors,
# ):
#     bitset_intersection(
#         suffix_neighbors_of_vertex, 
#         graph.rows[vertex], 
#         suffix_vertices
#     )
#     for part in range(parts_used):
#         if _is_greedy_part_for_vertex(
#             part,
#             suffix_vertices,
#             part_neighbors,
#             suffix_neighbors_of_vertex,
#             part_suffix_neighbors,
#         ):
#             return part
#     return -1


# cdef inline bint _is_greedy_part_for_vertex(
#     int part,
#     bitset_t suffix_vertices,
#     binary_matrix_t part_neighbors,
#     bitset_t suffix_neighbors_of_vertex,
#     binary_matrix_t part_suffix_neighbors,
# ):
#     bitset_intersection(
#         part_suffix_neighbors.rows[part],
#         part_neighbors.rows[part],
#         suffix_vertices
#     )
#     return bitset_eq(part_suffix_neighbors.rows[part], suffix_neighbors_of_vertex)


# cdef inline bint _check_state_seen(
#     dict seen_states,
#     int* seen_entries,
#     bitset_t prefix_vertices,
#     bitset_t suffix_vertices,
#     int parts_used,
#     binary_matrix_t part_neighbors,
#     binary_matrix_t part_suffix_neighbors,
#     int max_prefix_length,
#     int max_seen_entries
# ):
#     bitset_complement(prefix_vertices, suffix_vertices)
#     cdef int prefix_len = bitset_len(prefix_vertices)
#     if prefix_len > max_prefix_length:
#         return False

#     cdef frozenset frozen_prefix_vertices = frozenset(bitset_list(prefix_vertices))
#     cdef frozenset frozen_part_neighbors = _build_frozen_part_neighbors(
#         suffix_vertices, parts_used, part_neighbors, part_suffix_neighbors)
#     cdef dict seen_part_neighbors
#     cdef int parts_used_before
#     cdef bint state_seen = False
#     if frozen_prefix_vertices in seen_states:
#         seen_part_neighbors = seen_states[frozen_prefix_vertices]
#         if frozen_part_neighbors in seen_part_neighbors:
#             parts_used_before = seen_part_neighbors[frozen_part_neighbors]
#             if parts_used_before <= parts_used:
#                 state_seen = True
#             else:
#                 seen_part_neighbors[frozen_part_neighbors] = parts_used
#         elif seen_entries[0] < max_seen_entries:
#             seen_part_neighbors[frozen_part_neighbors] = parts_used
#             seen_entries[0] += 1
#     elif seen_entries[0] < max_seen_entries:
#         seen_states[frozen_prefix_vertices] = {frozen_part_neighbors: parts_used}
#         seen_entries[0] += 1
    
#     return state_seen


# cdef inline _build_frozen_part_neighbors(
#     bitset_t suffix_vertices,
#     int parts_used, 
#     binary_matrix_t part_neighbors,
#     binary_matrix_t part_suffix_neighbors
# ):
#     cdef set suffix_part_neighbors = set()
#     cdef frozenset part_suffix_neighbors_set 
#     for part in range(parts_used):
#         bitset_intersection(
#             part_suffix_neighbors.rows[part], part_neighbors.rows[part], suffix_vertices)
#         part_suffix_neighbors_set = frozenset(bitset_list(part_suffix_neighbors.rows[part]))
#         suffix_part_neighbors.add(part_suffix_neighbors_set)
#     return frozenset(suffix_part_neighbors)

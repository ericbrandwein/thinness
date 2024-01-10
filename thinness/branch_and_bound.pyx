# cython: profile=True
from sage.graphs.graph import Graph
from sage.data_structures.bitset import Bitset
from sage.data_structures.binary_matrix cimport *
from sage.graphs.base.static_dense_graph cimport dense_graph_init
from cysignals.memory cimport check_malloc, sig_malloc, sig_free

from .reduce import reduce_graph


def calculate_thinness_with_branch_and_bound(graph: Graph, lower_bound: int = 1, upper_bound: int = None) -> int:
    components = [graph.subgraph(component) for component in graph.connected_components()]
    for component in components:
        component.relabel()
    return max(calculate_thinness_of_connected_graph(component, lower_bound, upper_bound) for component in components)


def calculate_thinness_of_connected_graph(graph: Graph, lower_bound: int = 1, upper_bound: int = None) -> int:
    """upper_bound is exclusive."""
    if upper_bound is None:
        upper_bound = max(graph.pathwidth(), 1)
    if upper_bound == 1:
        return 1

    cdef binary_matrix_t adjacency_matrix
    dense_graph_init(adjacency_matrix, graph)
    
    cdef bitset_t suffix_non_neighbors_of_vertex
    bitset_init(suffix_non_neighbors_of_vertex, adjacency_matrix.n_cols)

    cdef bitset_t prefix_vertices
    bitset_init(prefix_vertices, adjacency_matrix.n_cols)
    
    cdef bitset_t suffix_vertices
    bitset_init(suffix_vertices, adjacency_matrix.n_cols)
    bitset_complement(suffix_vertices, suffix_vertices)

    cdef int* part_of = <int*>sig_malloc(sizeof(int) * adjacency_matrix.n_cols)

    cdef binary_matrix_t parts_for_vertices
    binary_matrix_init(parts_for_vertices, adjacency_matrix.n_cols, upper_bound - 1)
    
    branch_and_bound_thinness = _branch_and_bound(
        graph=adjacency_matrix,
        part_of=part_of,
        parts_used=0,
        prefix_vertices=prefix_vertices,
        suffix_vertices=suffix_vertices,
        suffix_non_neighbors_of_vertex=suffix_non_neighbors_of_vertex,
        parts_for_vertices=parts_for_vertices,
        lower_bound=lower_bound,
        upper_bound=upper_bound - 1
    )

    binary_matrix_free(adjacency_matrix)
    bitset_free(prefix_vertices)
    bitset_free(suffix_vertices)
    bitset_free(suffix_non_neighbors_of_vertex)
    sig_free(part_of)
    binary_matrix_free(parts_for_vertices)

    return (branch_and_bound_thinness or upper_bound)


cdef _branch_and_bound(
    binary_matrix_t graph,
    int* part_of,
    int parts_used,
    bitset_t prefix_vertices,
    bitset_t suffix_vertices,
    bitset_t suffix_non_neighbors_of_vertex,
    binary_matrix_t parts_for_vertices,
    int lower_bound, 
    int upper_bound
):
    if bitset_isempty(suffix_vertices) and parts_used <= upper_bound:
        return parts_used
    
    best_solution_found = None
    cdef int vertex = bitset_next(suffix_vertices, 0)
    cdef bitset_s* parts_for_vertex
    cdef int part
    while vertex != -1:
        _get_available_parts_for_vertex(graph, vertex, part_of, parts_used, prefix_vertices, suffix_vertices, suffix_non_neighbors_of_vertex, parts_for_vertices)
        parts_for_vertex = parts_for_vertices.rows[vertex]
        bitset_add(prefix_vertices, vertex)
        bitset_discard(suffix_vertices, vertex)
        part = bitset_next(parts_for_vertex, 0)
        while part != -1:
            if part < upper_bound:
                current_parts_used = max(parts_used, part + 1)
                part_of[vertex] = part
                current_solution = _branch_and_bound(
                    graph, 
                    part_of, 
                    current_parts_used,
                    prefix_vertices,
                    suffix_vertices, 
                    suffix_non_neighbors_of_vertex,
                    parts_for_vertices,
                    max(lower_bound, current_parts_used), 
                    upper_bound
                )
                if current_solution is not None:
                    best_solution_found = current_solution
                    upper_bound = best_solution_found - 1
                    if upper_bound < lower_bound:
                        bitset_remove(prefix_vertices, vertex)
                        bitset_add(suffix_vertices, vertex)
                        return best_solution_found
            part = bitset_next(parts_for_vertex, part + 1)
        bitset_remove(prefix_vertices, vertex)
        bitset_add(suffix_vertices, vertex)
        vertex = bitset_next(suffix_vertices, vertex + 1)
    return best_solution_found


cdef inline void _get_available_parts_for_vertex(
    binary_matrix_t graph, 
    int vertex, 
    int* part_of, 
    int parts_used,
    bitset_t prefix_vertices,
    bitset_t suffix_vertices,
    bitset_t suffix_non_neighbors_of_vertex,
    binary_matrix_t parts_for_vertices
):
    bitset_complement(suffix_non_neighbors_of_vertex, graph.rows[vertex])
    bitset_intersection(suffix_non_neighbors_of_vertex, suffix_non_neighbors_of_vertex, suffix_vertices)
    bitset_discard(suffix_non_neighbors_of_vertex, vertex)

    cdef bitset_s* parts_for_vertex = parts_for_vertices.rows[vertex]
    bitset_set_first_n(parts_for_vertex, parts_used)
    cdef int order_vertex = bitset_next(prefix_vertices, 0)
    while order_vertex != -1:
        if not bitset_are_disjoint(graph.rows[order_vertex], suffix_non_neighbors_of_vertex):
            bitset_discard(parts_for_vertex, part_of[order_vertex])
            if bitset_isempty(parts_for_vertex):
                break
        order_vertex = bitset_next(prefix_vertices, order_vertex + 1)

    bitset_add(parts_for_vertex, parts_used)
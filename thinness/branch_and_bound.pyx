# cython: profile=True
from sage.graphs.graph import Graph
from sage.data_structures.bitset import Bitset
from sage.data_structures.binary_matrix cimport *
from sage.graphs.base.static_dense_graph cimport dense_graph_init

from .reduce import reduce_graph


def calculate_thinness_with_branch_and_bound(graph: Graph, lower_bound: int = 1, upper_bound: int = None) -> int:
    components = [graph.subgraph(component) for component in graph.connected_components()]
    for component in components:
        component.relabel()
    return max(calculate_thinness_of_connected_graph(component, lower_bound, upper_bound) for component in components)


def calculate_thinness_of_connected_graph(graph: Graph, lower_bound: int = 1, upper_bound: int = None) -> int:
    """upper_bound is exclusive."""
    if graph.is_interval():
        return 1
    lower_bound = max(lower_bound, 2)
    if upper_bound is None:
        upper_bound = graph.order()
    upper_bound = min(upper_bound, _get_best_upper_bound(graph))

    cdef binary_matrix_t adjacency_matrix
    dense_graph_init(adjacency_matrix, graph)
    cdef bitset_t suffix_non_neighbors_of_vertex
    bitset_init(suffix_non_neighbors_of_vertex, adjacency_matrix.n_cols)
    cdef bitset_t suffix_vertices
    bitset_init(suffix_vertices, adjacency_matrix.n_cols)
    bitset_complement(suffix_vertices, suffix_vertices)
    cdef list part_of = [0] * graph.order()
    branch_and_bound_thinness = _branch_and_bound(
        graph=adjacency_matrix,
        order=[],
        part_of=part_of, 
        parts_used=0,
        suffix_vertices=suffix_vertices,
        suffix_non_neighbors_of_vertex=suffix_non_neighbors_of_vertex,
        lower_bound=lower_bound,
        upper_bound=upper_bound - 1
    )
    binary_matrix_free(adjacency_matrix)
    bitset_free(suffix_vertices)
    bitset_free(suffix_non_neighbors_of_vertex)

    return (branch_and_bound_thinness or upper_bound)


def _get_best_upper_bound(graph: Graph) -> int:
    """Get an upper bound for the thinness of a graph that is connected and not interval."""
    n = graph.order()
    return min(
        graph.pathwidth(),
        n - graph.diameter(),
        n - graph.clique_number(),
        n - graph.independent_set(value_only=True),
    )


cdef _branch_and_bound(
    binary_matrix_t graph, 
    list order, 
    list part_of, 
    int parts_used,
    bitset_t suffix_vertices,
    bitset_t suffix_non_neighbors_of_vertex,
    int lower_bound, 
    int upper_bound
):
    if set(order) == set(range(graph.n_cols)) and parts_used <= upper_bound:
        return parts_used
    
    best_solution_found = None
    cdef int vertex = bitset_next(suffix_vertices, 0)
    while vertex != -1:
        parts_for_vertex = _get_available_parts_for_vertex(graph, vertex, order, part_of, parts_used, suffix_vertices, suffix_non_neighbors_of_vertex)
        order.append(vertex)
        bitset_discard(suffix_vertices, vertex)
        for part in parts_for_vertex:
            if part < upper_bound:
                current_parts_used = max(parts_used, part + 1)
                part_of[vertex] = part
                current_solution = _branch_and_bound(
                    graph, 
                    order, 
                    part_of, 
                    current_parts_used,
                    suffix_vertices, 
                    suffix_non_neighbors_of_vertex,
                    max(lower_bound, current_parts_used), 
                    upper_bound
                )
                if current_solution is not None:
                    best_solution_found = current_solution
                    upper_bound = best_solution_found - 1
                    if upper_bound < lower_bound:
                        order.pop()
                        return best_solution_found
        order.pop()
        bitset_add(suffix_vertices, vertex)
        vertex = bitset_next(suffix_vertices, vertex + 1)
    return best_solution_found


cdef inline _get_available_parts_for_vertex(
    binary_matrix_t graph, 
    int vertex, 
    list order, 
    list part_of, 
    int parts_used, 
    bitset_t suffix_vertices,
    bitset_t suffix_non_neighbors_of_vertex
):
    bitset_complement(suffix_non_neighbors_of_vertex, graph.rows[vertex])
    bitset_intersection(suffix_non_neighbors_of_vertex, suffix_non_neighbors_of_vertex, suffix_vertices)
    bitset_discard(suffix_non_neighbors_of_vertex, vertex)

    parts_for_vertex = Bitset(range(parts_used), capacity=parts_used + 1)
    for order_vertex in order:
        if not bitset_are_disjoint(graph.rows[order_vertex], suffix_non_neighbors_of_vertex):
            parts_for_vertex.discard(part_of[order_vertex])
            if not parts_for_vertex:
                break

    parts_for_vertex.add(parts_used + 1)
    return parts_for_vertex
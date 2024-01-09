# cython: profile=True
cimport cython
from sage.graphs.graph import Graph
from sage.data_structures.bitset import Bitset

from .consistent_solution import ConsistentSolution
from .reduce import reduce_graph


def calculate_thinness_with_branch_and_bound(graph: Graph, lower_bound: int = 1, upper_bound: int = None) -> int:
    components = [graph.subgraph(component) for component in graph.connected_components()]
    for component in components:
        component.relabel()
    return max(calculate_thinness_of_connected_graph(component, lower_bound, upper_bound) for component in components)


def calculate_thinness_of_connected_graph(graph: Graph, lower_bound: int = 1, upper_bound: int = None) -> int:
    graph = reduce_graph(graph)
    if graph.order() <= 1:
        return 1
    upper_bound = upper_bound or graph.order() - graph.diameter()
    pathwidth = graph.pathwidth()
    adjacency_matrix = graph.adjacency_matrix()
    matrix_of_bitsets = [Bitset(''.join(str(element) for element in row)) for row in adjacency_matrix]
    vertices_in_order = Bitset()

    branch_and_bound_thinness = _branch_and_bound(graph.order(), matrix_of_bitsets, Graph(), [], vertices_in_order, lower_bound, min(upper_bound, pathwidth - 1))
    return branch_and_bound_thinness or pathwidth


cdef _branch_and_bound(n: int, graph: list[Bitset], compatibility_graph: Graph, order: list[int], vertices_in_order: Bitset, lower_bound: int, upper_bound: int):
    suffix_vertices = Bitset(range(n))
    if order:
        suffix_vertices -= vertices_in_order
    if not suffix_vertices:
        classes_used = _minimum_partition_size(compatibility_graph)
        if classes_used <= upper_bound:
            return classes_used
    
    best_solution_found = None
    for vertex in suffix_vertices:
        current_solution = _get_best_solution_with_vertex(n, graph, compatibility_graph, order, vertices_in_order, suffix_vertices, lower_bound, upper_bound, vertex)
        if current_solution is not None:
            best_solution_found = current_solution
            upper_bound = best_solution_found - 1
            if upper_bound < lower_bound:
                return best_solution_found
    return best_solution_found


cdef inline _get_best_solution_with_vertex(n: int, graph: list[Bitset], compatibility_graph: Graph, order: list[int], vertices_in_order: Bitset, suffix_vertices: Bitset, lower_bound: int, upper_bound: int, vertex: int):
    _add_vertex_to_compatibility_graph(graph, compatibility_graph, order, suffix_vertices, vertex)
    order.append(vertex)
    vertices_in_order.add(vertex)
    classes_used = _minimum_partition_size(compatibility_graph)
    thinness = None
    if classes_used <= upper_bound:
        thinness = _branch_and_bound(n, graph, compatibility_graph, order, vertices_in_order, max(lower_bound, classes_used), upper_bound)
    order.pop()
    vertices_in_order.remove(vertex)
    compatibility_graph.delete_vertex(vertex)
    return thinness


cdef inline void _add_vertex_to_compatibility_graph(graph: list[Bitset], compatibility_graph: Graph, order: list[cython.int], suffix_vertices: Bitset, vertex: cython.int):
    compatibility_graph.add_vertex(vertex)
    suffix_non_neighbors_of_vertex = graph[vertex].complement().intersection(suffix_vertices)
    if vertex in suffix_non_neighbors_of_vertex:
        suffix_non_neighbors_of_vertex.remove(vertex)
    
    for order_vertex in order:
        if not graph[order_vertex].isdisjoint(suffix_non_neighbors_of_vertex):
            compatibility_graph.add_edge(order_vertex, vertex)
        

cdef _minimum_partition_size(compatibility_graph: Graph):
    return compatibility_graph.clique_number()

# cython: profile=True
cimport cython
from sage.graphs.graph import Graph
from sage.data_structures.bitset import Bitset

from .reduce import reduce_graph


def calculate_thinness_with_branch_and_bound(graph: Graph, lower_bound: int = 1, upper_bound: int = None) -> int:
    components = [graph.subgraph(component) for component in graph.connected_components()]
    for component in components:
        component.relabel()
    return max(calculate_thinness_of_connected_graph(component, lower_bound, upper_bound) for component in components)


def calculate_thinness_of_connected_graph(graph: Graph, lower_bound: int = 1, upper_bound: int = None) -> int:
    """upper_bound is exclusive."""
    graph, reduced_thinness = reduce_graph(graph)
    if graph.is_interval():
        return 1 + reduced_thinness
    lower_bound = max(lower_bound, 2)
    if upper_bound is None:
        upper_bound = graph.order()
    else:
        upper_bound -= reduced_thinness
    upper_bound = min(upper_bound, _get_best_upper_bound(graph))
    adjacency_matrix = graph.adjacency_matrix()
    matrix_of_bitsets = [Bitset(''.join(str(element) for element in row)) for row in adjacency_matrix]
    part_of = [0] * graph.order()

    branch_and_bound_thinness = _branch_and_bound(matrix_of_bitsets, [], part_of, 0, lower_bound, upper_bound - 1)
    return (branch_and_bound_thinness or upper_bound) + reduced_thinness


def _get_best_upper_bound(graph: Graph) -> int:
    """Get an upper bound for the thinness of a graph that is connected and not interval."""
    n = graph.order()
    return min(
        graph.pathwidth(),
        n - graph.diameter(),
        n - graph.clique_number(),
        n - graph.independent_set(value_only=True),
    )


cdef _branch_and_bound(graph: list[Bitset], order: list[int], part_of: list[int], classes_used: int, lower_bound: int, upper_bound: int):
    if set(order) == set(range(len(graph))) and classes_used <= upper_bound:
        return classes_used
    
    suffix_vertices = Bitset(range(len(graph)))
    if order:
        suffix_vertices -= Bitset(order)
    best_solution_found = None
    for vertex in suffix_vertices:
        parts_for_vertex = _get_available_parts_for_vertex(graph, vertex, order, part_of, classes_used, suffix_vertices)
        order.append(vertex)
        for part in parts_for_vertex:
            if part < upper_bound:
                current_classes_used = max(classes_used, part + 1)
                part_of[vertex] = part
                current_solution = _branch_and_bound(graph, order, part_of, current_classes_used, max(lower_bound, current_classes_used), upper_bound)
                if current_solution is not None:
                    best_solution_found = current_solution
                    upper_bound = best_solution_found - 1
                    if upper_bound < lower_bound:
                        order.pop()
                        return best_solution_found
        order.pop()
    return best_solution_found


cdef inline object _get_available_parts_for_vertex(graph: list[Bitset], vertex: int, order: list[int], part_of: list[int], classes_used: int, suffix_vertices: Bitset):
    parts_for_vertex = Bitset(range(classes_used + 1))
    suffix_non_neighbors_of_vertex = graph[vertex].complement().intersection(suffix_vertices)
    if vertex in suffix_non_neighbors_of_vertex:
        suffix_non_neighbors_of_vertex.remove(vertex)
    
    for order_vertex in order:
        if part_of[order_vertex] in parts_for_vertex and not graph[order_vertex].isdisjoint(suffix_non_neighbors_of_vertex):
            parts_for_vertex.remove(part_of[order_vertex])
    return parts_for_vertex
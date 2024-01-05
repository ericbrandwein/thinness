from sage.graphs.graph import Graph
from sage.graphs.graph_decompositions.vertex_separation import vertex_separation

from .vertex_separation import solution_from_vertex_separation
from .consistent_solution import ConsistentSolution


def calculate_thinness_with_branch_and_bound(graph: Graph, lower_bound: int = 1, upper_bound: int = None):
    upper_bound = upper_bound or graph.order() - 1
    _, linear_layout = vertex_separation(graph)
    initial_solution = solution_from_vertex_separation(graph, linear_layout)
    branch_and_bound_solution = _branch_and_bound(graph, Graph(), [], lower_bound, min(upper_bound, initial_solution.thinness - 1))
    return branch_and_bound_solution or initial_solution


def _branch_and_bound(graph: Graph, compatibility_graph: Graph, order: list[int], lower_bound: int, upper_bound: int) -> ConsistentSolution:
    suffix_vertices = set(graph.vertices()) - set(order)
    if not suffix_vertices:
        current_partition = _minimum_partition(compatibility_graph)
        classes_used = len(current_partition)
        if classes_used <= upper_bound:
            current_partition = [set(part) for part in current_partition]
            return ConsistentSolution(list(order), current_partition)
    
    best_solution_found = None
    for vertex in suffix_vertices:
        current_solution = _get_best_solution_with_vertex(graph, compatibility_graph, order, suffix_vertices, lower_bound, upper_bound, vertex)
        if current_solution is not None:
            best_solution_found = current_solution
            upper_bound = best_solution_found.thinness - 1
            if upper_bound < lower_bound:
                return best_solution_found
    return best_solution_found


def _get_best_solution_with_vertex(graph: Graph, compatibility_graph: Graph, order: list[int], suffix_vertices: set[int], lower_bound: int, upper_bound: int, vertex: int) -> ConsistentSolution:
    _add_vertex_to_compatibility_graph(graph, compatibility_graph, order, suffix_vertices, vertex)
    order.append(vertex)
    current_partition = _minimum_partition(compatibility_graph)
    classes_used = len(current_partition)
    solution = None
    if classes_used <= upper_bound:
        solution = _branch_and_bound(graph, compatibility_graph, order, max(lower_bound, classes_used), upper_bound)
    order.pop()
    compatibility_graph.delete_vertex(vertex)
    return solution


def _add_vertex_to_compatibility_graph(graph: Graph, compatibility_graph: Graph, order: list[int], suffix_vertices: set[int], vertex: int):
    compatibility_graph.add_vertex(vertex)
    for suffix_vertex in suffix_vertices:
        if suffix_vertex != vertex and not graph.has_edge(suffix_vertex, vertex):
            neighbors_in_order = set(graph.neighbors(suffix_vertex)).intersection(set(order))
            for neighbor in neighbors_in_order:
                compatibility_graph.add_edge(neighbor, vertex)


def _minimum_partition(compatibility_graph: Graph):
    return compatibility_graph.coloring()

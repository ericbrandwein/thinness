import itertools
import functools
from sage.graphs.graph import Graph

from .consistent_solution import ConsistentSolution


def _has_same_vertices(G: Graph, solution: ConsistentSolution):
    vertices = set(G.vertices())
    return vertices == set(solution.order) and len(solution.order) == G.order() and \
        functools.reduce(set.union, solution.partition, set()) == vertices


def verify_solution(G: Graph, solution: ConsistentSolution):
    """Verify that the given solution is a valid thinness ordering and partition for the graph G.
    
    This implementation uses the O(n^2) algorithm that only checks the thinness condition for each pair (u, v) of vertices that are consecutive within their class, which can be shown to be equivalent to the straightforward O(n^3) implementation that checks all triples (u, v, w).
    """
    if not _has_same_vertices(G, solution):
        return False
    position = {vertex: i for i, vertex in enumerate(solution.order)}
    for part in solution.partition:
        vertices_in_order = sorted(part, key=position.get)
        for first_vertex, second_vertex in itertools.pairwise(vertices_in_order):
            for third_vertex in solution.order[position[second_vertex]+1:]:
                if G.has_edge(first_vertex, third_vertex) and not G.has_edge(second_vertex, third_vertex):
                    return False
    return True

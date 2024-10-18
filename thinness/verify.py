import itertools
import functools
from sage.graphs.graph import Graph

from .consistent_solution import ConsistentSolution


def _has_same_vertices(G: Graph, solution: ConsistentSolution):
    vertices = set(G.vertices())
    return vertices == set(solution.order) and len(solution.order) == G.order() and \
        functools.reduce(set.union, solution.partition, set()) == vertices


def verify_solution(G: Graph, solution: ConsistentSolution):
    return _has_same_vertices(G, solution) and not any(
        solution.part_of(u) == solution.part_of(v) and G.has_edge(u, w) and not G.has_edge(v, w)
        for u, v, w in itertools.combinations(solution.order, 3)
    )

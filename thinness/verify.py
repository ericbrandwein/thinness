import itertools
from sage.graphs.graph import Graph

from .consistent_solution import ConsistentSolution


def verify_solution(G: Graph, solution: ConsistentSolution):
    return G.order() == len(solution.order) and not any(
        solution.part_of(u) == solution.part_of(v) and G.has_edge(u, w) and not G.has_edge(v, w)
        for u, v, w in itertools.combinations(solution.order, 3)
    )

from sage.misc.randstate import set_random_seed
from sage.graphs.graph_generators import graphs
from sage.graphs.graph_decompositions.vertex_separation import vertex_separation

import pyximport; pyximport.install()
from thinness.z3 import Z3ThinnessSolver


def profile():
    set_random_seed(0)
    n = 10
    solver = Z3ThinnessSolver(n)
    for _ in range(100):
        graph = graphs.RandomGNP(n, 0.5)
        upper_bound, _ = vertex_separation(graph)
        solver.solve(graph, upper_bound=upper_bound-1)


profile()
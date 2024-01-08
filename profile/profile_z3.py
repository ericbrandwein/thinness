from sage.misc.randstate import set_random_seed
from sage.graphs.graph_generators import graphs

import pyximport; pyximport.install()
from thinness.z3 import Z3ThinnessSolver


def profile():
    set_random_seed(0)
    n = 10
    solver = Z3ThinnessSolver(n)
    for _ in range(100):
        solver.solve(graphs.RandomGNP(n, 0.5))


profile()
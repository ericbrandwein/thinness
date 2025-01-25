from sage.misc.randstate import set_random_seed
from sage.graphs.graph_generators import graphs

import pyximport; pyximport.install()
from thinness.branch_and_bound import calculate_thinness


def profile():
    set_random_seed(0)
    n = 10
    for _ in range(1000):
        graph = graphs.RandomGNP(n, 0.5)
        calculate_thinness(graph)


profile()
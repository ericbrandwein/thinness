from sage.graphs.graph_generators import graphs
from sage.misc.randstate import set_random_seed

import pyximport; pyximport.install()
from thinness.order import thinness_of_order


def profile():
    set_random_seed(0)
    n = 10
    for _ in range(100):
        graph = graphs.RandomGNP(n, 0.5)
        order = graph.vertices()
        thinness_of_order(graph, order)


profile()    

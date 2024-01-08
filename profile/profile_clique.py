from sage.graphs.graph_generators import graphs
from sage.misc.randstate import set_random_seed

from thinness.compatibility import build_compatibility_graph


def profile():
    set_random_seed(0)
    n = 10
    for _ in range(100):
        graph = graphs.RandomGNP(n, 0.5)
        order = graph.vertices()
        compatibility_graph = build_compatibility_graph(graph, order)
        compatibility_graph.clique_number()


profile()    

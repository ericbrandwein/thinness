import itertools

from sage.graphs.graph import Graph


def is_incompatible_triple(graph, u, v, w):
    return graph.has_edge(u, w) and not graph.has_edge(v, w)


def build_compatibility_graph(graph, order):
    compatibility_graph = Graph([graph.vertices(), []])
    for u, v, w in itertools.combinations(order, 3):
        if is_incompatible_triple(graph, u, v, w):
            compatibility_graph.add_edge(u, v, label=w)
    return compatibility_graph

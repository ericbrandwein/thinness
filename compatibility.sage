import itertools

from sage.graphs.graph import Graph

from z3_thinness import calculate_thinness_with_z3


def is_incompatible_triple(graph, u, v, w):
    return graph.has_edge(u, w) and not graph.has_edge(v, w)


def build_compatibility_graph(graph, order):
    compatibility_graph = Graph(graph.order())
    for u, v, w in itertools.combinations(order, 3):
        if is_incompatible_triple(graph, u, v, w):
            compatibility_graph.add_edge(u, v, label=w)
    return compatibility_graph


graph = Graph('FWfRo')
thinness, order, partition = calculate_thinness_with_z3(graph)
order = [0, 2, 1, 4, 3, 5, 6]
print(order)
build_compatibility_graph(graph, order).show(edge_labels=True)

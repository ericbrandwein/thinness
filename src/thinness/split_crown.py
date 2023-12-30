import itertools
from math import ceil
from sage.graphs.graph import Graph
from sage.graphs.graph_generators import graphs
from . import ConsistentSolution


def build_split_crown_graph(vertices_per_side: int):
    complete_graph = graphs.CompleteGraph(vertices_per_side)
    independent_graph = Graph(vertices_per_side)
    graph = complete_graph.disjoint_union(independent_graph, labels="integers")
    for i, j in itertools.permutations(range(vertices_per_side), 2):
        graph.add_edge(i, j + vertices_per_side)
    return graph


def thinness_of_split_crown_graph(vertices_per_side: int):
    return ConsistentSolution(_order(vertices_per_side), _partition(vertices_per_side))


def _order(vertices_per_side: int):
    order = []
    order.extend(range(vertices_per_side + 1, vertices_per_side*2, 2))
    for i in range(0, vertices_per_side, 2):
        order.append(i)
        if i+1 < vertices_per_side:
            order.append(i+1)
        order.append(i+vertices_per_side)
    return order


def _partition(vertices_per_side: int):
    parts = ceil(vertices_per_side / 2)
    partition = [set() for _ in range(parts)]
    parts_per_vertices = itertools.chain(
        enumerate(range(vertices_per_side+1, 2*vertices_per_side, 2)),
        enumerate(range(0, vertices_per_side, 2)),
        enumerate(range(1, vertices_per_side, 2)),
        enumerate(range(vertices_per_side, 2*vertices_per_side - 2, 2), start=1),
    )

    for part, vertex in parts_per_vertices:
        partition[part].add(vertex)

    if vertices_per_side % 2 == 0:
        partition[0].add(vertices_per_side*2-2)
    return partition
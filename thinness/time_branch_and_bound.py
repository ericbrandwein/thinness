import timeit
import itertools

from sage.graphs.graph_generators import graphs
from sage.graphs.graph import Graph 

from thinness.branch_and_bound import calculate_thinness_with_branch_and_bound


def profile():
    n = 15
    for _ in range(100):
        graph = graphs.RandomGNP(n, 0.5)
        calculate_thinness_with_branch_and_bound(graph)


def crown_graph(vertices_per_side: int) -> Graph:
    graph = Graph(2*vertices_per_side)
    for u, v in itertools.permutations(range(vertices_per_side), 2):
        graph.add_edge(u, v + vertices_per_side)
    return graph


def thinness_of_chordal_graphs(n):
    for graph in graphs.nauty_geng(f'-c -T {n}'):
        calculate_thinness_with_branch_and_bound(graph)


if __name__ == '__main__':
    for n in range(1, 10):
        graph = crown_graph(n)
        print(n, timeit.timeit("calculate_thinness_with_branch_and_bound(graph, max_prefix_length=100, max_seen_entries=1_600_000)", globals=globals(), number=1))
    
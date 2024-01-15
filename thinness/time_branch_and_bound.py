import timeit
import itertools
import textwrap

from sage.graphs.graph_generators import graphs
from sage.graphs.graph import Graph
from sage.misc.randstate import set_random_seed

from thinness.branch_and_bound import calculate_thinness_with_branch_and_bound


def profile(n):
    graph = graphs.RandomGNP(n, 0.8)
    calculate_thinness_with_branch_and_bound(graph, max_seen_entries=1_600_000)


def crown_graph(vertices_per_side: int) -> Graph:
    graph = Graph(2*vertices_per_side)
    for u, v in itertools.permutations(range(vertices_per_side), 2):
        graph.add_edge(u, v + vertices_per_side)
    return graph


def thinness_of_chordal_graphs(n):
    for graph in graphs.nauty_geng(f'-c -T {n}'):
        calculate_thinness_with_branch_and_bound(graph, max_seen_entries=1_600_000)


if __name__ == '__main__':
    set_random_seed(0)
    print("Crown graphs:")
    for n in range(2, 12):
        graph = crown_graph(n)
        print(textwrap.indent(
            text=f'{n}:\t{timeit.timeit("calculate_thinness_with_branch_and_bound(graph, max_seen_entries=1_600_000)", globals=globals(), number=1)}',
            prefix='  '
        ))
    set_random_seed(0)
    print("Random GNM graphs:")
    for n in range(10, 20):
        print(textwrap.indent(text=f'{n}:', prefix='  '))
        for density in [0.2, 0.5, 0.8]:
            m = n*(n-1)//2 * density
            times = []
            for _ in range(10):
                graph = graphs.RandomGNM(n, m)
                times.append(
                    timeit.timeit("calculate_thinness_with_branch_and_bound(graph, max_seen_entries=1_600_000)", globals=globals(), number=1)
                )
            print(textwrap.indent(
                text=f'density {density}: {sum(times)/len(times)}',
                prefix='    '
            ))

    
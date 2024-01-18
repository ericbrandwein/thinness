import itertools
import textwrap
from linetimer import CodeTimer

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


def time_crown_graphs():
    for n in range(2, 20):
        graph = crown_graph(n)
        print(textwrap.indent(
            text=f'{n}:\t{time_calculation(graph)}',
            prefix='  '
        ))


def time_random_graphs():
    for n in range(10, 20):
        print(textwrap.indent(text=f'{n}:', prefix='  '))
        for density in [0.2, 0.5, 0.8]:
            m = n*(n-1)//2 * density
            times = []
            for _ in range(10):
                graph = graphs.RandomGNM(n, m)
                times.append(time_calculation(graph))
            print(textwrap.indent(
                text=f'density {density}: {sum(times)/len(times)}',
                prefix='    '
            ))


def time_complement_of_nK2():
    for n in range(1, 14):
        graph = (graphs.CompleteGraph(2) * n).complement()
        print(textwrap.indent(
            text=f'{n}:\t{time_calculation(graph)}',
            prefix='  '
        ))


def time_grid_graphs():
    for rows in range(2, 9):
        for cols in range(2, rows + 1):
            graph = graphs.Grid2dGraph(rows, cols)
            time = time_calculation(graph)
            print(textwrap.indent(
                text=f'{rows}x{cols}:\t{time}',
                prefix='  '
            ))


def time_calculation(graph: Graph):
    code_timer = CodeTimer(silent=True)
    with code_timer:
        calculate_thinness_with_branch_and_bound(graph, max_seen_entries=1_600_000, max_prefix_length=20)
    return code_timer.took / 1000


if __name__ == '__main__':
    print("Crown graphs:")
    time_crown_graphs()

    set_random_seed(0)
    print("Random GNM graphs:")
    time_random_graphs()

    print("Complement of n*K2 graphs:")
    time_complement_of_nK2()

    print("Grid graphs:")
    time_grid_graphs()
    
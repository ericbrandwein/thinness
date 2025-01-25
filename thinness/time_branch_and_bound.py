import itertools
import textwrap
from math import ceil
from linetimer import CodeTimer

from sage.graphs.graph_generators import graphs
from sage.graphs.graph import Graph
from sage.misc.randstate import set_random_seed

from thinness.branch_and_bound import calculate_thinness


def profile(n):
    graph = graphs.RandomGNP(n, 0.8)
    calculate_thinness(graph, max_seen_entries=1_600_000)


def thinness_of_chordal_graphs(n):
    for graph in graphs.nauty_geng(f'-c -T {n}'):
        calculate_thinness(graph, max_seen_entries=1_600_000)


def split_graphs(n):
    return graphs.nauty_geng(f'-c -S {n}')


def crown_graph(vertices_per_side: int) -> Graph:
    graph = Graph(2*vertices_per_side)
    for u, v in itertools.permutations(range(vertices_per_side), 2):
        graph.add_edge(u, v + vertices_per_side)
    return graph


def time_crown_graphs():
    for n in range(2, 20):
        graph = crown_graph(n)
        print(textwrap.indent(
            text=f'{n}:\t{time_calculation(graph)}',
            prefix='  '
        ))


def cylinder_graph(rows: int, columns: int):
    graph = graphs.Grid2dGraph(rows, columns)
    for row in range(rows):
        graph.add_edge((row, 0), (row, columns - 1))
    return graph


def time_cylinder_graphs():
    for rows in range(2, 9):
        for columns in range(2, 9):
            graph = cylinder_graph(rows, columns)
            print(textwrap.indent(
                text=f'{rows}x{columns}:\t{time_calculation(graph, return_thinness=True)}',
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
            print(textwrap.indent(
                text=f'{rows}x{cols}:\t{time_calculation(graph, return_thinness=True)}',
                prefix='  '
            ))


def time_outerplanar_graphs():
    for n in range(2, 20):
        print(n)
        for graph in graphs(n):
            if graph.is_circular_planar():
                time_taken, thinness = time_calculation(graph, return_thinness=True)
                if thinness > 2:
                    print(f'Graph with thinness {thinness} found: {graph.graph6_string()}')
                    break


def time_calculation(graph: Graph, return_thinness=False):
    code_timer = CodeTimer(silent=True)
    with code_timer:
        thinness = calculate_thinness(graph, max_seen_entries=1_600_000, max_prefix_length=20)
    time_taken = code_timer.took / 1000 
    return time_taken if not return_thinness else (time_taken, thinness)


def thinness_of_split_graphs():
    for n in range(2, 20, 2):
        for graph in split_graphs(n):
            thinness = calculate_thinness(graph, max_seen_entries=1_600_000)
            if thinness == ceil(n/4):
                print(f'{graph.graph6_string()} with {n} vertices has thinness {thinness}')


def combination_graph(n):
    graph = graphs.CompleteGraph(n)
    for u, v in itertools.combinations(range(n), 2):
        new_vertex = graph.add_vertex()
        graph.add_edges([(new_vertex, u), (new_vertex, v)])
    return graph


def thinness_of_combination_graphs():
    for n in range(3, 10):
        graph = combination_graph(n)
        thinness = calculate_thinness(graph, max_seen_entries=1_500_000)
        print(f'{n}: {thinness}')


def some_graph(n):
    graph = graphs.CompleteGraph(n)
    vertices_to_connect = ceil(n / 2)
    for v in graph.vertices():
        new_vertex = graph.add_vertex()
        for i in range(vertices_to_connect):
            graph.add_edge((v + i) % n, new_vertex)
    print(graph.graph6_string())
    return graph

def thinness_of_some_graphs():
    for n in range(2, 15):
        graph = some_graph(n)
        thinness = calculate_thinness(graph, max_seen_entries=1_500_000)
        print(f'{n}: {thinness}')

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
    
    print("Cylinder graphs:")
    time_cylinder_graphs()

    # print(cylinder_graph(3,2).graph6_string())

    # time_outerplanar_graphs()

    # thinness_of_split_graphs()

    # thinness_of_combination_graphs()

    thinness_of_some_graphs()

    
    
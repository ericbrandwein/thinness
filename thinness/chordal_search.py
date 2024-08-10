from math import floor

from sage.graphs.graph_generators import graphs
from sage.graphs.graph import Graph
import cysignals

from thinness.branch_and_bound import calculate_thinness
from thinness.data import load_graphs_by_thinness
from thinness.helpers import has_induced_subgraph
from thinness.reduce import reduce_graph
from thinness.compatibility import build_compatibility_graph

# J??FCtVJzv_ is the only graph found with 11 vertices
def thinness_of_chordal_graphs(n: int):
    graphs_by_thinness = load_graphs_by_thinness(n-1)
    for thinness, current_graphs in graphs_by_thinness.items():
        graphs_by_thinness[thinness] = [graph for graph in current_graphs if graph.is_chordal()]
    minimal_chordals_found = []
    for i, graph in enumerate(chordal_graphs(n)):
        try:
            thinness = calculate_thinness(graph)
            if thinness > 2 and not has_induced_subgraph(graph, graphs_by_thinness[thinness]):
                minimal_chordals_found.append(graph)
                print()
                print(graph.graph6_string(), thinness)
        except cysignals.signals.SignalError as ex:
            print('Error calculating thinness of', graph.graph6_string())
            print(ex)
        
        print(f'Analized {i} graphs', end='\r')
    print(minimal_chordals_found)


def thinness_of_split_graphs(n: int):
    graphs_by_thinness = load_graphs_by_thinness(n-1)
    minimal_splits_found = []
    for i, graph in enumerate(split_graphs(n)):
        thinness = calculate_thinness(graph)
        if thinness > 2 and not has_induced_subgraph(graph, graphs_by_thinness[thinness]):
            minimal_splits_found.append(graph.graph6_string())
            print()
            print(graph.graph6_string(), thinness)
        print(f'Analyzed {i} graphs', end='\r', flush=True)
    print(minimal_splits_found)


def chordal_graphs(n: int):
    return graphs.nauty_geng(f'-c -T {n}')


def split_graphs(n: int):
    return graphs.nauty_geng(f'-c -S {n}')


def minmal_chordal_thinness_3_graph_with_11_vertices():
    return Graph('J??FCtVJzv_')


def try_to_reduce_minmal_graph():
    graph = minmal_chordal_thinness_3_graph_with_11_vertices()
    _, reduced_thinness = reduce_graph(graph)
    if reduced_thinness == 0:
        print('Could not reduce')
    else:
        print('Can be reduced')


def test_thinness_of_weird_graph():
    external_edges = Graph({
        5: [0,2,4],
        6: [1,2,3],
        7: [0,1],
        8: [0,2,3],
        9: [1,2,4],
        10: [3,4]
    })

    for internal_edges in graphs(5):
        graph = external_edges.union(internal_edges)
        thinness = calculate_thinness(graph)
        if thinness < 3:
            print(graph.graph6_string(), thinness)


# Seems to be that the thinness of the grid graph i x j is floor(min(i,j) / 2 + 1)
def thinness_of_grid_graphs():
    for rows in range(2, 20):
        for columns in range(2, min(rows + 1, 9)):
            graph = graphs.Grid2dGraph(rows, columns)
            thinness = calculate_thinness(graph, max_prefix_length=20, max_seen_entries=1_600_000)
            print(f'{rows}x{columns}: {thinness}')
            assert thinness == floor(min(rows, columns) / 2 + 1)


def thinness_of_half_grid_graphs():
    for n in range(2, 12):
        graph = half_grid_graph(n)
        thinness = calculate_thinness(graph, max_prefix_length=20, max_seen_entries=1_600_000)
        print(f'{n}: {thinness}')
    graph = half_grid_graph(12)
    thinness = calculate_thinness(graph, lower_bound=4, upper_bound=5, max_prefix_length=20, max_seen_entries=1_600_000)
    print(f'{n}: {thinness}')


def half_grid_graph(n: int) -> Graph:
    graph = Graph(n*n)
    for row in range(n):
        for col in range(n):
            if row + col < n - 1:
                vertex = row + col*n
                right = vertex + n
                up = vertex + 1
                graph.add_edge(vertex, right)
                graph.add_edge(vertex, up)
    return graph


def thinness_of_grid_graph_without_last_vertices():
    for n in range(4, 10, 2):
        print(f'{n}x{n}:')
        graph = graphs.Grid2dGraph(n, n)
        for i in range(n):
            graph.delete_vertex((n-1, i))
            thinness = calculate_thinness(graph)
            print(f'  Thinness without last {i+1} vertices:', thinness)


# Minimal subgraph with thinness 3: Mh`HGcG@GC_H?C?A_
def thinness_of_induced_subgraphs_of_grid():
    graph = graphs.Grid2dGraph(4, 4)
    for subgraph in graph.connected_subgraph_iterator():
        thinness = calculate_thinness(subgraph)
        if thinness >= 3:
            print(subgraph.graph6_string(), thinness)


def solution_for_subgraph_of_grid4x4():
    graph = Graph('Mh`HGcG@GC_H?C?A_')
    solution = calculate_thinness(graph, certificate=True)
    print(solution)
    print(build_compatibility_graph(graph, solution.order).graph6_string())


def thinness_of_trees(n):
    NUMBER_OF_TREES = [1,1,1,1,2,3,6,11,23,47,106,235,551,1301,3159,
        7741,19320,48629,123867,317955,823065,2144505,
        5623756,14828074,39299897,104636890,279793450,
        751065460,2023443032,5469566585,14830871802,
        40330829030,109972410221,300628862480,
        823779631721,2262366343746,6226306037178
    ]

    for i, graph in enumerate(graphs.trees(n)):
        thinness = calculate_thinness(graph)
        if i % 1000 == 0:
            print(f'Analyzed {i+1}/{NUMBER_OF_TREES[n]} trees of order {n}', end='\r', flush=True)


def thinness_of_random_tree():
    

if __name__ == '__main__':
    for n in range(1, 20):
        thinness_of_trees(n)

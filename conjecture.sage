#!/usr/bin/env sage

from data import load_graphs_from_csv
from z3_thinness import calculate_thinness_with_z3
from compatibility import build_compatibility_graph
from sage.graphs.graph_generators import graphs
from sage.graphs.graph import Graph
from shower import show_graph, show_compatibility_graph
from math import ceil


def get_chordal_minimal_graphs(thinness=3):
    return [
        graph.graph6_string()
        for graph in load_graphs_from_csv(f'data/thinness-{thinness}.csv') 
        if graph.is_chordal()
    ]


# Conjecture: Asteroid graphs of kernel size k have thinness ceil(k / 2)
def asteroidize_graph(graph, asteroid=Graph(1)):
    kernel_vertices = list(graph.vertices())
    for i in kernel_vertices:
        new_asteroid = asteroid.copy()
        graph = graph + new_asteroid
        first_asteroid_vertex = graph.order() - new_asteroid.order()
        for j in kernel_vertices:
            if j != i:
                graph.add_edge(j, first_asteroid_vertex)
    return graph


def asteroid_graph(kernel_size=5):
    graph = graphs.CompleteGraph(kernel_size)
    return asteroidize_graph(graph)
    

# Every asteroid of every subgraph of K5 has thinness >= 3
def check_conjecture(kernel_size=5):
    for graph in graphs(kernel_size):
        graph = asteroidize_graph(graph)
        k, _, _ = calculate_thinness_with_z3(graph)
        if k < ceil(kernel_size / 2):
            print(f'Counterexample: {graph.graph6_string()}')
            return False
    return True


# Strong conjecture: Having an asteroidal quintuple implies thinness >= 3
# INVALID
def counterexample_of_strong_conjecture():
    graph = graphs.CompleteGraph(5)
    kernel_vertices = list(graph.vertices())
    for i in kernel_vertices:
        new_vertex = graph.add_vertex()
        graph.add_edge(i, new_vertex)
    thinness, _, _ = calculate_thinness_with_z3(graph)
    return graph.graph6_string(), thinness



# Strongish conjecture: Having a complete kernel of order 5 and adding an asteroid with thinness 2 for each vertex implies thinness >= 4
# INVALID
def counterexample_of_strongish_conjecture():
    asteroid = asteroid_graph(3)
    graph = graphs.CompleteGraph(5)
    new_graph = asteroidize_graph(graph, asteroid)
    thinness, order, partition = calculate_thinness_with_z3(new_graph)
    print(thinness, order, partition) # 3 [8, 7, 10, 20, 6, 9, 5, 21, 18, 19, 22, 17, 33, 31, 4, 0, 29, 32, 34, 30, 3, 1, 11, 2, 28, 23, 27, 25, 24, 15, 12, 26, 13, 16, 14] {0: 2, 1: 3, 2: 3, 3: 1, 4: 2, 5: 3, 6: 2, 7: 3, 8: 2, 9: 3, 10: 2, 11: 1, 12: 1, 13: 3, 14: 1, 15: 3, 16: 2, 17: 2, 18: 1, 19: 2, 20: 1, 21: 2, 22: 2, 23: 3, 24: 2, 25: 2, 26: 2, 27: 2, 28: 3, 29: 3, 30: 1, 31: 1, 32: 1, 33: 1, 34: 1}
    return new_graph, thinness

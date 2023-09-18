#!/usr/bin/env sage

from helpers import load_graphs_from_csv
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


# Conjecture: Asteroid graphs of kernel size k with 1 free vertex in kernel have thinness ceil(k / 2)

def asteroidize_graph(graph):
    kernel_vertices = list(graph.vertices())
    for i in kernel_vertices:
        new_vertex = i + "'"
        graph.add_vertex(new_vertex)
        for j in kernel_vertices:
            if j != i:
                graph.add_edge(j, new_vertex)
    return graph


def asteroid_graph(kernel_size=5):
    graph = graphs.CompleteGraph(kernel_size)
    graph.relabel({0: 'a', 1: 'b', 2: 'c', 3: 'd', 4: 'e'})
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


graph = asteroid_graph()
# show_graph(graph)
# Maybe d' is always in the clique in G<?
order = ["a'", "b'", "c'", "d'", "e'", "c", "a", "b", "d", "e"]
# _, order, _ = calculate_thinness_with_z3(graph)
show_compatibility_graph(build_compatibility_graph(graph, order))
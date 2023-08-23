#!/usr/bin/env sage

from helpers import load_graphs_from_csv
from z3_thinness import calculate_thinness_with_z3
from compatibility import build_compatibility_graph
from sage.graphs.graph_generators import graphs


def get_chordal_minimal_graphs(thinness=3):
    return [
        graph.graph6_string()
        for graph in load_graphs_from_csv(f'data/thinness-{thinness}.csv') 
        if graph.is_chordal()
    ]


# Conjecture: Asteroid graphs of kernel size k with 1 free vertex in kernel have thinness ceil(k / 2)

def asteroid_graph(kernel_size=9, free_vertices_in_kernel=1):
    graph = graphs.CompleteGraph(kernel_size)
    non_free = kernel_size - free_vertices_in_kernel
    for i in range(kernel_size):
        new_vertex = graph.add_vertex()
        for j in range(i, i + non_free):
            kernel_vertex = j % kernel_size
            graph.add_edge(kernel_vertex, new_vertex)
    return graph

graph = asteroid_graph(5)

graph.show()
k, order, partition = calculate_thinness_with_z3(graph)
build_compatibility_graph(graph, order).show(method='js', edge_labels=True, link_distance=100, charge=-500, link_strength=0.5)
print(k)
print(order)
print(partition)

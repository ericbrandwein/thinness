from itertools import permutations
from tqdm import tqdm

from sage.graphs.graph import Graph
from sage.graphs.digraph import DiGraph
from sage.combinat.set_partition import SetPartitions

from .data import load_graphs_by_thinness
from .verify import verify_solution
from .consistent_solution import ConsistentSolution
from thinness.shower import show_graph_with_js

def get_implications_digraph(graph: Graph, colors: dict) -> DiGraph:
    implications_digraph = DiGraph()
    implications_digraph.add_vertices(permutations(graph.vertices(), 2))
    add_type_one_implications(graph, implications_digraph, colors)
    add_type_two_implications(graph, implications_digraph, colors)
    return implications_digraph
    

def add_type_one_implications(graph: Graph, implications_digraph: DiGraph, colors: dict):
    for u, v in permutations(graph.vertices(), 2):
        if colors[u] == colors[v]:
            for w in graph.neighbors(u):
                if not graph.has_edge(v, w) and v != w:
                    implications_digraph.add_edge((u, v), (w, v))


def add_type_two_implications(graph: Graph, implications_digraph: DiGraph, colors: dict):
    for u, v in permutations(graph.vertices(), 2):
        if not graph.has_edge(u, v):
            for w in graph.neighbors(v):
                if colors[u] == colors[w]:
                    implications_digraph.add_edge((u, v), (u, w))


def is_consistent_1(graph: Graph, colors: dict) -> bool:
    implications_digraph = get_implications_digraph(graph, colors)
    return not has_self_coupled_components(implications_digraph)


def has_self_coupled_components(implications_digraph: DiGraph) -> bool:
    for component in implications_digraph.strongly_connected_components():
        if any((v,u) in component for u, v in component):
            return True
        
    return False


def search_counterexamples_to_1():
    """
    Counterexample found:
GCRb`w
Partition:
{{0, 1, 2, 4, 7}, {3, 5, 6}}
  
  Counterexample found:
H?BcrpU
Partition:
{{0, 1, 3, 4, 5, 6}, {2, 7, 8}}
  
  Counterexample found:
H?bBbRP
Partition:
{{0, 1, 3, 5, 7}, {2, 4, 6, 8}}
  
  Counterexample found:
H?bBVbU
Partition:
{{0, 1, 2, 4, 6}, {3, 5, 7, 8}}
  
  Counterexample found:
H?`edbg
Partition:
{{0, 1, 2, 4, 5}, {3, 6, 7, 8}}
  
  Counterexample found:
H?`ed`w
Partition:
{{0, 4, 6, 7, 8}, {1, 2, 3, 5}}
  
  Counterexample found:
H?`ed_}
Partition:
{{0, 4, 7, 8}, {1, 2, 3, 5, 6}}
"""
    graphs_by_thinness = load_graphs_by_thinness()
    graphs = graphs_by_thinness[3]
    for graph in tqdm(graphs):
        for partition in SetPartitions(graph.vertices(), 2):
            colors = partition_to_colors(partition)
            if is_consistent_1(graph, colors):
                print("Counterexample found:")
                print(graph.graph6_string())
                print("Partition:")
                print(partition)
                break


def counterexample_to_1():
    return Graph('GCRb`w'), [{0, 1, 2, 4, 7}, {3, 5, 6}]


def partition_to_colors(partition: set) -> dict:
    colors = {}
    for i, part in enumerate(partition):
        for vertex in part:
            colors[vertex] = i
    return colors


def has_consistent_ordering(graph: Graph, partition: list[set]) -> bool:
    for ordering in permutations(graph.vertices()):
        solution = ConsistentSolution(ordering, partition)
        if verify_solution(graph, solution):
            return True
    return False


def show_counterexample_to_1():
    graph, partition = counterexample_to_1()
    implications_digraph = get_implications_digraph(graph, partition_to_colors(partition))
    delete_isolated_vertices(implications_digraph)
    show_graph_with_js(implications_digraph)
    # implications_digraph.show(method='js')
    

def delete_isolated_vertices(implications_digraph: DiGraph):
    for vertex in implications_digraph.vertices():
        if implications_digraph.degree(vertex) == 0:
            implications_digraph.delete_vertex(vertex)


def is_consistent_2():
    """Add the obvious transitivity implications to the implications digraph."""
    pass


if __name__ == "__main__":
    graph, partition = counterexample_to_1()
    implications_digraph = get_implications_digraph(graph, partition_to_colors(partition))
    delete_isolated_vertices(implications_digraph)
    for i, component in enumerate(implications_digraph.strongly_connected_components()):
        implications_digraph.subgraph(component).plot().save(f'implications_digraph_{i}.png')
    implications_digraph.plot().save('implications_digraph.png')
    # graphplot.set_edges(arrowsize=5)
    # graphplot.plot().save(f'implications_digraph.png')
    # graph.plot(partition=partition).save('counterexample_to_1.png')


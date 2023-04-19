from graph_reader import read_graph
from calculate_thinness import calculate_thinness, verify_solution
from show_graph import show_graph
import networkx as nx
from utils import all_subsets


def graph_extensions(G):
    for subset in all_subsets(G.nodes):
        new_graph = G.copy()
        new_graph.add_edges_from((new_node, old_node) for old_node in subset)
        yield new_graph


# Is there a 9-vertex graph with thinness 5?
co4K2 = read_graph("co-4K2")
new_node = 9
found = False
for graph in graph_extensions(co4K2):
    new_solution = calculate_thinness(graph, lower_bound=4, upper_bound=5)
    if not verify_solution(graph, new_solution):
        print("Solution is not correct!")
        print(new_solution)
        show_graph(graph)
    if new_solution.number_of_classes == 5:
        print("Found a graph with thinness 5!")
        nx.write_adjlist(graph, "adjlits/9-nodes-5-thinness.adjlist")
        found = True
        show_graph(graph)
        break

if not found:
    print("No graph with thinness 5 and 9 nodes found.")


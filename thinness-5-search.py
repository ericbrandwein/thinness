from graph_reader import read_graph
from calculate_thinness import calculate_thinness, verify_solution
from show_graph import show_graph
import networkx as nx
from utils import all_subsets


# Is there a 9-vertex graph with thinness 5?
co4K2 = read_graph("co-4K2")
new_node = 9
found = False
for subset in all_subsets(co4K2.nodes):
    print(subset)
    new_graph = co4K2.copy()
    new_graph.add_edges_from((new_node, old_node) for old_node in subset)
    new_solution = calculate_thinness(new_graph, lower_bound=4, upper_bound=5)
    if not verify_solution(new_graph, new_solution):
        print("Solution is not correct!")
        print(new_solution)
        show_graph(new_graph)
    if new_solution.number_of_classes == 5:
        print("Found a graph with thinness 5!")
        nx.write_adjlist(new_graph, "adjlits/9-nodes-5-thinness.adjlist")
        found = True
        show_graph(new_graph)
        break

if not found:
    print("No graph with thinness 5 and 9 nodes found.")


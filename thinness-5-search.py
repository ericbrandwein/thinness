from graph_reader import read_graph
from calculate_thinness import calculate_thinness_backtracking
from itertools import combinations, chain
from show_graph import show_graph
import networkx as nx


def all_subsets(iterable):
    s = list(iterable)
    return chain.from_iterable(combinations(s, r) for r in range(len(s)+1))


# Is there a 9-vertex graph with thinness 5?
co4K2 = read_graph("co-4K2")
new_node = 9
found = False
for subset in all_subsets(co4K2.nodes):
    print(subset)
    new_graph = co4K2.copy()
    new_graph.add_edges_from((new_node, old_node) for old_node in subset)
    new_thinness = calculate_thinness_backtracking(new_graph, lower_bound=4, upper_bound=5)
    if new_thinness == 5:
        print("Found a graph with thinness 5!")
        nx.write_adjlist(new_graph, "adjlits/9-nodes-5-thinness.adjlist")
        found = True
        show_graph(new_graph)
        break

if not found:
    print("No graph with thinness 5 and 9 nodes found.")


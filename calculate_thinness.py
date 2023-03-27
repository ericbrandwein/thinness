import networkx as nx
import matplotlib.pyplot as plt
import itertools
from math import factorial


processed_orderings = 0

def show_graph(G):
    nx.draw(G, with_labels=True)
    plt.show()


def generate_constraints_graph(G, ordering):
    constraints_graph = nx.Graph()
    constraints_graph.add_nodes_from(G)
    # If three ordered nodes (u,v,w) are such that u is connected to w
    # but v is not connected to w, then (u,v) is an edge in the constraints graph.
    for (u, v, w) in itertools.combinations(ordering, 3):
        if G.has_edge(u, w) and not G.has_edge(v, w):
            constraints_graph.add_edge(u, v)
    return constraints_graph


def cocomparability_coloring(graph):
    coloring = nx.coloring.greedy_color(graph)
    return len(set(coloring.values()))


def calculate_thinness_for_ordering(G, ordering):
    constraints_graph = generate_constraints_graph(G, ordering)
    number = cocomparability_coloring(constraints_graph)
    global processed_orderings, total_orderings
    processed_orderings += 1
    if processed_orderings % 10000 == 0:
        print(f"{processed_orderings}/{total_orderings}, Remaining: {total_orderings - processed_orderings}")
    return number


def calculate_thinness(G):
    nodes = list(G.nodes())
    return min(
        calculate_thinness_for_ordering(G, permutation)
        for permutation in itertools.permutations(nodes)
    )


G = nx.read_edgelist("graph.txt")
show_graph(G)
total_orderings = factorial(G.number_of_nodes())
print("Number of orderings:", total_orderings)
print("Processed:")

print(calculate_thinness(G))


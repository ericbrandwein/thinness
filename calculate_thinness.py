import networkx as nx
import matplotlib.pyplot as plt
import itertools
import sys

GRAPHS_DIR = "adjlists"
GRAPHS_FILE_EXTENSION = ".adjlist"

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
    return number


def insertions(iterable, element):
    for i in range(len(iterable) + 1):
        yield iterable[:i] + [element] + iterable[i:]


def calculate_thinness_starting_with_suborder(G, ordering, remaining_nodes, best_thinness: int):
    subG = nx.induced_subgraph(G, ordering)
    thinness = calculate_thinness_for_ordering(subG, ordering)
    if thinness >= best_thinness:
        return best_thinness
    if len(ordering) == G.number_of_nodes():
        return thinness
    next_node = remaining_nodes.pop()
    for new_ordering in insertions(ordering, next_node):
        thinness = calculate_thinness_starting_with_suborder(G, new_ordering, remaining_nodes, best_thinness)
        if thinness < best_thinness:
            best_thinness = thinness
    remaining_nodes.add(next_node)
    return best_thinness


def calculate_thinness_backtracking(G):
    nodes = set(G.nodes())
    ordering = [nodes.pop()]
    return calculate_thinness_starting_with_suborder(G, ordering, nodes, G.number_of_nodes())


def parse_arguments():
    if len(sys.argv) < 2:
        return "graph"
    else:
        return sys.argv[1]


def read_graph(file):
    filename = f"{GRAPHS_DIR}/{file}{GRAPHS_FILE_EXTENSION}"
    print("Reading graph from file:", filename)
    return nx.read_adjlist(filename)

def main():
    graph_file = parse_arguments()
    G = read_graph(graph_file)
    
    print("Thinness:", calculate_thinness_backtracking(G))
    show_graph(G)

if __name__ == "__main__":
    main()
    

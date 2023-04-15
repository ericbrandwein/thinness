import networkx as nx
import matplotlib.pyplot as plt
import itertools
import sys

GRAPHS_DIR = "adjlists"
GRAPHS_FILE_EXTENSION = ".adjlist"

def show_graph(G):
    nx.draw(G, with_labels=True)
    plt.show()

def find_first_adjacent(G, nodes, node):
    return next(
        (index for index, adjacent in enumerate(nodes) if G.has_edge(adjacent, node)), 
        None
    )


def add_last_constraints(G, constraints_graph, before, new_node):
    for u_index, u in enumerate(before):
        if G.has_edge(u, new_node):
            for v in before[u_index + 1:]:
                if not G.has_edge(v, new_node):
                    constraints_graph.add_edge(u, v)


def add_middle_constraints(G, constraints_graph, before, after, new_node):
    nonadjacent_after = [
        nonadjacent for nonadjacent in after if not G.has_edge(new_node, nonadjacent)
    ]
    for u in before:
        if find_first_adjacent(G, nonadjacent_after, u) is not None:
            constraints_graph.add_edge(u, new_node)
         

def add_first_constraints(G, constraints_graph, after, new_node):
    for v_index, v in enumerate(after):
        nonadjacent_v = [
            nonadjacent for nonadjacent in after[v_index + 1:] if not G.has_edge(v, nonadjacent)
        ]
        if find_first_adjacent(G, nonadjacent_v, new_node) is not None:
            constraints_graph.add_edge(new_node, v)


def add_constraints(G, constraints_graph, before, after, new_node):
    add_last_constraints(G, constraints_graph, before, new_node)
    add_middle_constraints(G, constraints_graph, before, after, new_node)
    add_first_constraints(G, constraints_graph, after, new_node)


def extend_constraints_graph(G, constraints_graph, ordering, new_node):
    new_graph = constraints_graph.copy()
    position = ordering.index(new_node)
    before = ordering[:position]
    after = ordering[position + 1:]
    add_constraints(G, new_graph, before, after, new_node)
    return new_graph


def cocomparability_coloring(graph):
    coloring = nx.coloring.greedy_color(graph)
    return len(set(coloring.values()))


def calculate_thinness_for_ordering(G, constraints_graph, ordering, new_node):
    constraints_graph = extend_constraints_graph(G, constraints_graph, ordering, new_node)
    number = cocomparability_coloring(constraints_graph)
    return number, constraints_graph


def insertions(iterable, element):
    for i in range(len(iterable) + 1):
        yield iterable[:i] + [element] + iterable[i:]


def calculate_thinness_starting_with_suborder(G, constraints_graph, ordering, new_node, remaining_nodes, best_thinness: int):
    subG = nx.induced_subgraph(G, ordering)
    thinness, constraints_graph = calculate_thinness_for_ordering(
        subG, constraints_graph, ordering, new_node
    )
    if thinness >= best_thinness:
        return best_thinness
    if len(ordering) == G.number_of_nodes():
        return thinness
    next_node = remaining_nodes.pop()
    for new_ordering in insertions(ordering, next_node):
        thinness = calculate_thinness_starting_with_suborder(
            G, constraints_graph, new_ordering, next_node, remaining_nodes, best_thinness
        )
        if thinness < best_thinness:
            best_thinness = thinness
    remaining_nodes.add(next_node)
    return best_thinness


def calculate_thinness_backtracking(G):
    nodes = set(G.nodes())
    ordering = [nodes.pop()]
    return calculate_thinness_starting_with_suborder(
        G, nx.Graph(), ordering, ordering[0], nodes, G.number_of_nodes()
    )


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
    # show_graph(G)

if __name__ == "__main__":
    main()
    

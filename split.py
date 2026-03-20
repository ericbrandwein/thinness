from sage import all
from sage.graphs.graph import Graph
from thinness.data import load_graphs_by_thinness
from thinness.branch_and_bound import calculate_thinness
from thinness.time_branch_and_bound import split_graphs


def split_minimal_thinness_3_graphs_up_to_10_vertices():
    graph_by_thinness = load_graphs_by_thinness()
    return [graph for graph in graph_by_thinness[3] if graph.is_split()]


"""It's actually 2"""
def thinness_of_split_graph_we_thought_had_thinness_3():
    graph = Graph(r'I?q\z|nBG')
    return calculate_thinness(graph)


def split_graphs_with_at_least_eleven_vertices():
    return (graph for graph in all.graphs.nauty_geng('-c 11:') if graph.is_split())


def split_graphs_of_thinness_3():
    return filter(lambda G: calculate_thinness(G) == 3, split_graphs_with_at_least_eleven_vertices())


def find_minimal_split_graphs_of_thinness_3():
    minimal_graphs = split_minimal_thinness_3_graphs_up_to_10_vertices()
    split_graphs = split_graphs_of_thinness_3()
    for graph in split_graphs:
        if not any(graph.subgraph_search(minimal, induced=True) for minimal in minimal_graphs):
            minimal_graphs.append(graph)
            yield graph
    

if __name__ == '__main__':
    print(r'I?q\z|nBG', "has thinness", thinness_of_split_graph_we_thought_had_thinness_3(), "instead of 3")
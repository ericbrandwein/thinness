from sage import all
from sage.graphs.graph import Graph
from thinness.data import load_graphs_by_thinness
from thinness.branch_and_bound import calculate_thinness
from thinness.time_branch_and_bound import split_graphs
from sage.graphs.graph_generators import graphs
from thinness.verify import verify_solution
from thinness.lean_spider import build_lean_spider_graph, thinness_of_lean_spider_graph


def split_minimal_thinness_3_graphs_up_to_10_vertices():
    graph_by_thinness = load_graphs_by_thinness()
    return [graph for graph in graph_by_thinness[3] if graph.is_split()]


"""It's actually 2"""
def thinness_of_split_graph_we_thought_had_thinness_3():
    graph = Graph(r'K?qXz~~Bf^`w')
    thick5 = Graph(r'I?~mz}~@w')
    if graph.subgraph_search(thick5, induced=True):
        print("SI es subgrafo inducido")
    else:
        print("NO es subgrafo inducido")
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
    #print(r'K?qXz~~Bf^`w', "has thinness", thinness_of_split_graph_we_thought_had_thinness_3(), "instead of 3")
    
    for i in range(5,100):
        Ls = build_lean_spider_graph(i)
        Cs = thinness_of_lean_spider_graph(i)
        if verify_solution(Ls,Cs):
            print("Funciono el orden para lean spider de ", i, " vertices con ", len(Cs.partition), " partes")

        else: 
            print("Rompe para lean spider de ", i, " vertices")
        
        #print("lean spider of ",i, "vertices",  Ls.graph6_string(), "has thinness", calculate_thinness(Ls, certificate=True))
        #print(Ls.edges())
        #print(verify_solution(Ls, calculate_thinness(Ls, certificate=True)))
    
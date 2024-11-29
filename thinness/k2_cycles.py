from sage.graphs.graph import Graph
from sage.graphs.graph_generators import graphs
from thinness.branch_and_bound import calculate_thinness
from thinness.data import load_graphs_by_thinness
from thinness.shower import show_graph
from tqdm import tqdm


def modular_cycle(module: Graph, size: int) -> Graph:
    graph = Graph()
    vertices = size * module.order()
    for i in range(size):
        graph = graph.disjoint_union(module, labels='integers')
    for i in range(size):
        first_vertex = i * module.order()
        for left_index in range(module.order()):
            for right_index in range(module.order()):
                graph.add_edge(left_index + first_vertex, (right_index + first_vertex + module.order()) % vertices)

    return graph


def modular_path(module: Graph, size: int) -> Graph:
    graph = Graph()
    for i in range(size):
        graph = graph.disjoint_union(module, labels='integers')
    for i in range(size-1):
        first_vertex = i * module.order()
        for left_index in range(module.order()):
            for right_index in range(module.order()):
                graph.add_edge(left_index + first_vertex, right_index + first_vertex + module.order())

    return graph


def K2_cycle(size: int):
    vertices = size*2
    graph = Graph(vertices)
    for i in range(0, vertices, 2):
        graph.add_edges([
            (i, (i+2) % vertices), 
            (i, (i+3) % vertices),
            (i+1, (i+2) % vertices),
            (i+1, (i+3) % vertices)
        ])
    return graph


def thinness_of_K2_cycles(max_size: int):
    for i in range(2, max_size + 1):
        graph = K2_cycle(i)
        thinness = calculate_thinness(graph, lower_bound=2)
        print(f'{i}: {thinness}')
        print(graph.graph6_string())


def thinness_of_modular_cycles(module: Graph, max_size: int):
    for i in range(2, max_size + 1):
        graph = modular_cycle(module, i)
        thinness = calculate_thinness(graph)
        print(f'{i}: {thinness}')
        print(graph.graph6_string())


def thinness_of_modular_paths(module: Graph, max_size: int):
    for i in range(2, max_size + 1):
        graph = modular_path(module, i)
        thinness = calculate_thinness(graph)
        print(f'{i}: {thinness}')
        print(graph.graph6_string())


def K2_union_complement(number_of_k2s):
    graph = Graph()
    K2 = graphs.CompleteGraph(2)
    for _ in range(number_of_k2s):
        graph = graph.disjoint_union(K2)
    return graph.complement()


def modular_product(module: Graph, graph: Graph):
    product = module*graph.order()
    for edge in graph.edges():
        for i in range(module.order()):
            for j in range(module.order()):
                vertex_left = edge[0]*module.order() + i
                vertex_right = edge[1]*module.order() + j
                product.add_edge(vertex_left, vertex_right)
    return product


    
def save_graph(graph):
    graph.plot().save('graph.png')


# thinness_of_modular_cycles(K2_union_complement(4), 12)


save_graph(modular_product(K2_union_complement(1), graphs.PathGraph(3)))


def check_every_5_modular_cycle_of_thin_2_graphs_has_thinness_6():
    i = 0
    for graph in load_graphs_by_thinness()[2]:
        cycle = modular_cycle(graph, 5)
        if calculate_thinness(cycle, lower_bound=2) != 6:
            print("FOUND COUNTEREXAMPLE!!!")
            print(f"Graph: {cycle.graph6_string()}")
            print(f"Module: {graph.graph6_string()}")
            break
        i+=1
        print(i)

# check_every_5_modular_cycle_of_thin_2_graphs_has_thinness_6()

from sage.graphs.graph import Graph
from sage.graphs.digraph import DiGraph
from sage.graphs.graph_generators import graphs
from thinness.branch_and_bound import calculate_thinness
from thinness.data import load_graphs_by_thinness
from thinness.shower import show_graph, show_solution
from thinness.compatibility import build_compatibility_graph
from thinness.consistent_solution import ConsistentSolution
from thinness.verify import verify_solution
from sage.graphs.graph_decompositions.modular_decomposition import *
from sage.graphs.graph_generators import graphs
import itertools
import random
from tqdm import tqdm


decomposition = modular_decomposition(graphs.CycleGraph(5))


class ModularCompatibilityDiGraph:
    def __init__(self):
        self.digraph = DiGraph()
        self.different_color_edges = set()

    def is_different_color_edge(self, u, v):
        return (u,v) in self.different_color_edges


def build_modular_compatibility_graph(graph: Graph, prime_node: Node):
    modular_compatibility_graph = ModularCompatibilityDiGraph()
    digraph = modular_compatibility_graph.digraph
    representatives = [find_a_vertex(child) for child in prime_node.children]
    for first_index, (first_child, first_representative) in enumerate(zip(prime_node.children, representatives)):
        for second_index, (second_child, second_representative) in enumerate(zip(prime_node.children, representatives)):
            if first_representative == second_representative or not graph.has_edge(first_representative, second_representative):
                continue
            first_complete = is_complete(first_child)
            second_complete = is_complete(second_child)
            if not first_complete or second_complete:
                digraph.add_edge(first_index, second_index)
            if not first_complete and not second_complete:
                modular_compatibility_graph.different_color_edges.add((first_index, second_index))
    return modular_compatibility_graph


def find_a_vertex(node: Node) -> int:
    if node.node_type == NodeType.NORMAL:
        return node.children[0]
    return find_a_vertex(node.children[0])


def is_complete(node: Node):
    node_type = node.node_type
    return node_type == NodeType.NORMAL or (
        node_type == NodeType.SERIES and all(child.node_type == NodeType.NORMAL for child in node.children)
    )


def get_vertices(node: Node) -> list[int]:
    if node.node_type == NodeType.NORMAL:
        return node.children
    return list(itertools.chain.from_iterable(get_vertices(child) for child in node.children))


def module_subgraph(graph: Graph, node: Node) -> Graph:
    vertices = get_vertices(node)
    return graph.subgraph(vertices)


def partitions(collection):
    if len(collection) == 1:
        yield [{collection[0]}]
        return
    first = collection[0]
    for smaller in partitions(collection[1:]):
        for n, subset in enumerate(smaller):
            yield smaller[:n] + [{first}.union(subset)] + smaller[n + 1:]
        yield [{first}] + smaller


def find_best_solution(thinnesses: list[int], prime_node: Node, modular_compatibility_graph: ModularCompatibilityDiGraph):
    best_value = sum(thinnesses)
    for order in itertools.permutations(list(range(len(prime_node.children)))):
        for partition in partitions(list(range(len(prime_node.children)))):
            solution = ConsistentSolution(order, partition)
            value = modular_solution_value(solution, thinnesses)
            if value < best_value and verify_modular_solution(solution, modular_compatibility_graph):
                best_value = value
    return best_value


def verify_modular_solution(solution: ConsistentSolution, modular_compatibility_graph: ModularCompatibilityDiGraph):
    digraph = modular_compatibility_graph.digraph
    for u, v in itertools.combinations(solution.order, 2):
        if solution.part_of(u) == solution.part_of(v) and (
           modular_compatibility_graph.is_different_color_edge(u, v) or
           (not digraph.has_edge(u, v) and digraph.has_edge(v, u))
        ):
            return False
    
    return verify_solution(digraph.to_undirected(), solution)


def modular_solution_value(solution: ConsistentSolution, thinnesses: list[int]) -> int:
    return sum(
        max(thinnesses[vertex] for vertex in part)
        for part in solution.partition
    )


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
    for i in range(6, max_size + 1):
        graph = modular_cycle(module, i)
        solution = calculate_thinness(graph, certificate=True)
        print(f'{i}: {solution}')
        show_graph(graph)
        show_graph(build_compatibility_graph(graph, solution.order))
        show_solution(graph, solution)
        input()


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
        graph = graph.disjoint_union(K2, labels='integers')
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


def thinness_of_C4_cycle_with_one_I2(): 
    graph = modular_product(K2_union_complement(2), graphs.PathGraph(5))
    I2 = Graph(2)
    graph = I2.disjoint_union(graph, labels='integers')
    for i in range(2):
        for j in range(4):
            graph.add_edge(i, 2 + j)
            graph.add_edge(i, graph.order() - 1 - j)

    return calculate_thinness(graph, lower_bound=2)


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


def test_modular_algorithm():
    for i in range(8, 100):
        counted = 0
        print(f"Order {i}")
        for graph in graphs(i):
            decomposition = modular_decomposition(graph)
            if decomposition.node_type == NodeType.PRIME:
                thinnesses = [calculate_thinness(module_subgraph(graph, node)) for node in decomposition.children]
                if max(thinnesses) >= 2:
                    counted += 1
                    best_found = find_best_solution(thinnesses, decomposition, build_modular_compatibility_graph(graph, decomposition))
                    actual = calculate_thinness(graph)
                    if best_found != actual:
                        print("FOUND COUNTEREXAMPLE!!!")
                        print(f"Graph: {graph.graph6_string()}")
                        print(f"Best found: {best_found}")
                        print(f"Actual: {actual}")
                        break
                    if counted % 10 == 0:
                        print(counted)
                    if counted == 1000:
                        break

def modular_incompatibility_algorithm_counterexample():
    return Graph('G?r@fw')


def test_modular_incompatibility_algorithm_counterexample():
    graph = modular_incompatibility_algorithm_counterexample()
    decomposition = modular_decomposition(graph)
    thinnesses = [calculate_thinness(module_subgraph(graph, node)) for node in decomposition.children]
    compatibility_graph = build_modular_compatibility_graph(graph, decomposition)
    algorithm_solution = find_best_solution(thinnesses, decomposition, compatibility_graph)
    assert(algorithm_solution != calculate_thinness(graph))


def transform_modules_to_K2_complements(graph: Graph, decomposition: Node, thinnesses: list[int]):
    representatives = [find_a_vertex(child) for child in decomposition.children]
    relabeling = {representative: i for i, representative in enumerate(representatives)}
    modules_graph = graph.subgraph(representatives).relabel(perm=relabeling, inplace=False)
    new_modules = [
        Graph(1) if is_complete(module) else K2_union_complement(thinness) 
        for thinness, module in zip(thinnesses, decomposition.children)
    ]
    new_graph = Graph()
    for module in new_modules:
        module.relabel(lambda x: new_graph.order() + x)
        new_graph = new_graph.union(module)

    for u, v in modules_graph.edges(labels=False):
        for first_vertex in new_modules[u].vertices():
            for second_vertex in new_modules[v].vertices():
                new_graph.add_edge(first_vertex, second_vertex)
    
    return new_graph


def simplify_modules(graph: Graph) -> Graph:
    decomposition = modular_decomposition(graph)
    thinnesses = [
        calculate_thinness(module_subgraph(graph, node))
        for node in decomposition.children
    ]
    return transform_modules_to_K2_complements(graph, decomposition, thinnesses)


def test_simplify_modules():
    for i in range(2, 100):
        print(f"Order {i}")
        for graph in tqdm(graphs(i)):
            decomposition = modular_decomposition(graph)
            thinnesses = [
                calculate_thinness(module_subgraph(graph, node))
                for node in decomposition.children
            ]
            if max(thinnesses) >= 2:
                reduced_graph = transform_modules_to_K2_complements(graph, decomposition, thinnesses)
                reduced_thinness = calculate_thinness(reduced_graph)
                actual_thinness = calculate_thinness(graph)
                if reduced_thinness != actual_thinness:
                    print("FOUND COUNTEREXAMPLE!!!")
                    print(f"Graph: {graph.graph6_string()}")
                    print(f"Reduced graph: {reduced_graph.graph6_string()}")
                    print(f"Reduced thinness: {reduced_thinness}")
                    print(f"Actual thinness: {actual_thinness}")
                    break
        

def simplify_modules_conterexample():
    return Graph('HCOf?z~')


def test_simplify_modules_conterexample():
    graph = simplify_modules_conterexample()
    simplified = simplify_modules(graph)
    assert(calculate_thinness(simplified) != calculate_thinness(graph))

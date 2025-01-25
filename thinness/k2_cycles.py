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
from thinness.z3 import Z3ThinnessSolver

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
    return (graphs.CompleteGraph(2) * number_of_k2s).complement()


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
            if decomposition.node_type == NodeType.PRIME:
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


def connected_graphs(n):
    return graphs.nauty_geng(f'-c {n}')


def graphs_with_thinness(thinness: int, max_order: int):
    for i in range(2, max_order + 1):
        for graph in connected_graphs(i):
            if calculate_thinness(graph) == thinness:
                yield graph


def test_simplify_modules_on_modular_products_of_unions():
    print('Calculating graphs with thinness 2...')
    thinness_2_graphs = list(graphs_with_thinness(2, 5))
    print('Calculated.')
    progress_bar = tqdm(total=len(thinness_2_graphs)**2)
    for half_module in thinness_2_graphs:
        module = half_module * 2
        for structure in thinness_2_graphs:
            graph = modular_product(module, structure)
            simplified_graph = simplify_modules(graph)
            thinness = calculate_thinness(graph)
            simplified_thinness = calculate_thinness(simplified_graph)
            if thinness != simplified_thinness:
                print("FOUND COUNTEREXAMPLE!!!")
                print(f"Module: {module.graph6_string()}")
                print(f"Structure: {structure.graph6_string()}")
                print(f"Graph: {graph.graph6_string()}")
                print(f"Simplified: {simplified_graph.graph6_string()}")
                break
            progress_bar.update()
    progress_bar.close()


# graph = Graph('PoCOZB~wVA{IwRFfbrw{}Ffk')
# solution = calculate_thinness(graph, certificate=True)
# show_solution(graph, solution)


def replace_vertex_by_module(graph: Graph, vertex, module: Graph):
    new_graph = graph.disjoint_union(module)
    new_graph.delete_vertex((0, vertex))
    for neighbor in graph.neighbors(vertex):
        for module_vertex in module.vertices():
            new_graph.add_edge((0, neighbor), (1, module_vertex))
    return new_graph


def search_counterexample_of_modules_are_consecutive():
    """
    Te cagué.
    Graph: FCrdo
    With one cycle: IEysKMD`g	2
    With two cycles: MEysKMD`kGO``@`A_	3
    """
    cycle = graphs.CycleGraph(4)
    two_cycles = cycle * 2
    for order in range(4, 100):
        print(f"Order {order}")
        for graph in tqdm(connected_graphs(order)):
            for vertex in graph:
                graph_with_one_cycle = replace_vertex_by_module(graph, vertex, cycle)
                graph_with_two_cycles = replace_vertex_by_module(graph, vertex, two_cycles)
                thinness_one_cycle = calculate_thinness(graph_with_one_cycle)
                thinness_two_cycles = calculate_thinness(graph_with_two_cycles)
                if thinness_one_cycle != thinness_two_cycles:
                    print("Te cagué.")
                    print(f"Graph: {graph.graph6_string()}")
                    print(f"With one cycle: {graph_with_one_cycle.graph6_string()}\t{thinness_one_cycle}")
                    print(f"With two cycles: {graph_with_two_cycles.graph6_string()}\t{thinness_two_cycles}")



def search_counterexample_of_flavias_conjecture():
    cycle = graphs.CycleGraph(4)
    two_cycles = cycle * 2
    three_cycles = cycle * 3
    for order in range(20, 100):
        print(f"Order {order}")
        for graph in tqdm(connected_graphs(order)):
            for vertex in graph:
                graph_with_two_cycles = replace_vertex_by_module(graph, vertex, two_cycles)
                thinness_two_cycles = calculate_thinness(graph_with_two_cycles)
                graph_with_three_cycles = replace_vertex_by_module(graph, vertex, three_cycles)
                thinness_three_cycles = calculate_thinness(graph_with_three_cycles)
                if thinness_three_cycles != thinness_two_cycles:
                    print("Te cagué.")
                    print(f"Graph: {graph.graph6_string()}")
                    print(f"With two cycles: {graph_with_two_cycles.graph6_string()}\t{thinness_two_cycles}")
                    print(f"With three cycles: {graph_with_three_cycles.graph6_string()}\t{thinness_three_cycles}")



# search_counterexample_of_modules_are_consecutive()

def counterexample_of_modules_are_consecutive():
    return Graph('FCrdo'), Graph('IEysKMD`g'), Graph('MEysKMD`kGO``@`A_')

# search_counterexample_of_flavias_conjecture()


def horizontal_union(graph1: Graph, graph2: Graph):
    graph1_pos = graph1.get_pos()
    graph2_pos = graph2.get_pos()
    new_graph1_pos = {
        (0, vertex): pos
        for vertex, pos in graph1_pos.items()
    }
    max_x_value_1 = max(pos[0] for pos in graph1_pos.values())
    min_x_value_2 = min(pos[0] for pos in graph2_pos.values())
    new_graph2_pos = {
        (1, vertex): (pos[0] + max_x_value_1 - min_x_value_2 + 1, pos[1])
        for vertex, pos in graph2_pos.items()
    }
    graph = graph1.disjoint_union(graph2)
    graph.set_pos({**new_graph1_pos, **new_graph2_pos})
    return graph


def horizontal_join(graph1: Graph, graph2: Graph):
    new_graph = horizontal_union(graph1, graph2)
    for vertex1 in graph1:
        for vertex2 in graph2:
            new_graph.add_edge((0, vertex1), (1, vertex2))
    return new_graph


def vertical_union(graph1: Graph, graph2: Graph):
    graph1_pos = graph1.get_pos()
    graph2_pos = graph2.get_pos()
    new_graph1_pos = {
        (0, vertex): pos
        for vertex, pos in graph1_pos.items()
    }
    max_y_value_1 = max(pos[1] for pos in graph1_pos.values())
    min_y_value_2 = min(pos[1] for pos in graph2_pos.values())
    new_graph2_pos = {
        (1, vertex): (pos[0], pos[1] + max_y_value_1 - min_y_value_2 + 1)
        for vertex, pos in graph2_pos.items()
    }
    graph = graph1.disjoint_union(graph2)
    graph.set_pos({**new_graph1_pos, **new_graph2_pos})
    return graph


def vertical_join(graph1: Graph, graph2: Graph):
    new_graph = vertical_union(graph1, graph2)
    for vertex1 in graph1:
        for vertex2 in graph2:
            new_graph.add_edge((0, vertex1), (1, vertex2))
    return new_graph


def upright_square_graph():
    cycle_graph = graphs.CycleGraph(4)
    cycle_graph.set_pos({
        0: (0, 0),
        1: (0, 1),
        3: (1, 0),
        2: (1, 1)
    })
    return cycle_graph


grid = graphs.Grid2dGraph(2, 3)
grid.add_edge((0, 0), (0, 2))
grid_join = horizontal_join(grid, grid)

cycle_graph = upright_square_graph()
two_cycles = horizontal_union(cycle_graph, cycle_graph)
three_cycles = horizontal_union(two_cycles, cycle_graph)

one_cycle_one_grid = vertical_union(grid, cycle_graph)
one_cycle_one_grid.relabel()
for cycle_vertex in range(cycle_graph.order()):
    for grid_vertex in (1, 2):
        one_cycle_one_grid.add_edge(grid_vertex, grid.order() + cycle_vertex)
solution = calculate_thinness(one_cycle_one_grid, certificate=True)
# show_solution(one_cycle_one_grid, solution)


two_cycles_one_grid = vertical_union(grid, two_cycles)
two_cycles_one_grid.relabel()
for cycle_vertex in range(two_cycles.order()):
    for grid_vertex in (1, 2):
        two_cycles_one_grid.add_edge(grid_vertex, grid.order() + cycle_vertex)
solution = calculate_thinness(two_cycles_one_grid, certificate=True)
# show_solution(two_cycles_one_grid, solution)

two_vertices = Graph(2)
two_vertices.set_pos({0: (0, 0), 1: (1, 0)})

column_graph = vertical_join(two_vertices, grid)
two_columns = horizontal_union(column_graph, column_graph)
graph = vertical_union(two_columns, two_cycles)
graph.relabel()
for cycle_vertex in range(two_cycles.order()):
    for grid_vertex in (3, 4):
        graph.add_edge(grid_vertex, two_columns.order() + cycle_vertex)
        graph.add_edge(grid_vertex + column_graph.order(), two_columns.order() + cycle_vertex)

for i in range(2):
    for j in range(2):
        graph.add_edge(i, column_graph.order() + j)

for grid_vertex in (3, 4):
    for other_grid_vertex in (3, 4):
        graph.add_edge(grid_vertex, column_graph.order() + other_grid_vertex)

last_graph = vertical_union(graph, two_vertices)
last_graph.relabel()
for i in range(2):
    for j in range(2):
        last_graph.add_edge(i, last_graph.order() - j - 1)
        last_graph.add_edge(column_graph.order() + i, last_graph.order() - j - 1)


solution = calculate_thinness(last_graph, certificate=True)
show_solution(last_graph, solution)



graph_two_cycles_module = vertical_union(grid_join, two_cycles)
graph_two_cycles_module.relabel()

graph_three_cycles_module = vertical_union(grid_join, three_cycles)
graph_three_cycles_module.relabel()

for cycle_vertex in range(two_cycles.order()):
    for grid_vertex in (1, 2, 6, 7):
        graph_two_cycles_module.add_edge(grid_vertex, grid_join.order() + cycle_vertex)

for cycle_vertex in range(three_cycles.order()):
    for grid_vertex in (1, 2, 6, 7):
        graph_three_cycles_module.add_edge(grid_vertex, grid_join.order() + cycle_vertex)


solution = calculate_thinness(graph_two_cycles_module, certificate=True)
# show_solution(graph_two_cycles_module, solution)
solution = calculate_thinness(graph_three_cycles_module, certificate=True)
# show_solution(graph_three_cycles_module, solution)


# graph = Graph('LhUN~~|~Nw~tW`')
# replaced_graph = replace_vertex_by_module(graph, 12, graphs.CycleGraph(4)*2)
# solution = calculate_thinness(replaced_graph, certificate=True)
# show_solution(replaced_graph, solution)
# graph.set_pos
# counterexample = counterexample_of_modules_are_consecutive()
# graph = Graph('G_GSZ_')
# other_graph = replace_vertex_by_module(counterexample[0], 3, graph)
# print(calculate_thinness(other_graph))


# show_solution(counterexample[1], calculate_thinness(counterexample[1], certificate=True))
# show_solution(counterexample[2], calculate_thinness(counterexample[2], certificate=True))

# print('Thinness of first graph according to z3:', Z3ThinnessSolver(counterexample[1].order()).solve(counterexample[1]))
# print('Thinness of second graph according to z3:', Z3ThinnessSolver(counterexample[2].order()).solve(counterexample[2]))
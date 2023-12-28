from math import floor, ceil
from sage.graphs.graph import Graph
from sage.graphs.graph_generators import graphs
from z3 import *
import itertools

from z3_thinness import Z3ThinnessSolver
from thinness import minimum_partition_for_vertex_order


def create_Kn_by_Knc(n: int):
    complete_graph = graphs.CompleteGraph(n)
    independent_graph = Graph(n)
    graph = complete_graph.disjoint_union(independent_graph, labels="integers")
    for i in range(n):
        for j in range(n):
            if i != j:
                graph.add_edge(i, n + j)
    return graph

# 3: Thinness: 2
# Order: [3, 1, 2, 4, 5, 0]
# Partition: {0: 1, 1: 1, 2: 2, 3: 1, 4: 2, 5: 2}
# 4: Thinness: 2
# Order: [4, 5, 3, 2, 1, 6, 7, 0]
# Partition: {0: 1, 1: 1, 2: 1, 3: 2, 4: 2, 5: 1, 6: 2, 7: 2}
# 5: Thinness: 3
# Order: [5, 6, 2, 7, 1, 4, 3, 0, 8, 9]
# Partition: {0: 2, 1: 2, 2: 2, 3: 1, 4: 3, 5: 1, 6: 2, 7: 1, 8: 3, 9: 3}
# 6: Thinness: 3
# Order: [6, 4, 0, 7, 3, 1, 8, 9, 10, 5, 11, 2]
# Partition: {0: 1, 1: 1, 2: 2, 3: 3, 4: 1, 5: 2, 6: 1, 7: 3, 8: 2, 9: 2, 10: 2, 11: 1}
# 7: Thinness: 4
# Order: [7, 8, 9, 3, 10, 4, 0, 11, 5, 12, 1, 2, 6, 13]
# Partition: {0: 3, 1: 1, 2: 1, 3: 3, 4: 4, 5: 1, 6: 2, 7: 3, 8: 2, 9: 1, 10: 1, 11: 1, 12: 2, 13: 3}
# 8: Thinness: 4
# Order: [8, 9, 5, 10, 11, 4, 12, 1, 13, 6, 0, 3, 14, 2, 7, 15]
# Partition: {0: 1, 1: 2, 2: 2, 3: 1, 4: 3, 5: 2, 6: 1, 7: 4, 8: 2, 9: 1, 10: 3, 11: 4, 12: 1, 13: 1, 14: 4, 15: 4}
# 9: Thinness: 5
# Order: [9, 7, 10, 11, 5, 12, 4, 3, 13, 14, 6, 15, 16, 0, 8, 17, 2, 1]
# Partition: {0: 5, 1: 1, 2: 3, 3: 3, 4: 5, 5: 2, 6: 1, 7: 3, 8: 4, 9: 3, 10: 5, 11: 2, 12: 4, 13: 4, 14: 4, 15: 4, 16: 4, 17: 3}
# 10: Thinness: 5
# Order: [10, 11, 12, 13, 14, 5, 15, 8, 2, 4, 3, 6, 0, 1, 7, 16, 17, 9, 18, 19]
# Partition: {0: 5, 1: 5, 2: 1, 3: 2, 4: 1, 5: 1, 6: 5, 7: 4, 8: 2, 9: 3, 10: 4, 11: 1, 12: 5, 13: 2, 14: 3, 15: 4, 16: 3, 17: 3, 18: 3, 19: 2}
# 11: Thinness: 6
# Order: [6, 11, 12, 13, 8, 14, 5, 15, 7, 9, 16, 17, 18, 0, 19, 1, 10, 4, 20, 21, 2, 3]
# Partition: {0: 6, 1: 6, 2: 5, 3: 1, 4: 2, 5: 1, 6: 3, 7: 4, 8: 2, 9: 6, 10: 5, 11: 2, 12: 4, 13: 6, 14: 1, 15: 5, 16: 5, 17: 5, 18: 5, 19: 5, 20: 5, 21: 6}
# 12: Thinness: 6
# Order: [12, 9, 13, 14, 15, 16, 6, 8, 1, 4, 2, 17, 18, 7, 19, 10, 20, 3, 21, 5, 22, 11, 0, 23]
# Partition: {0: 5, 1: 3, 2: 6, 3: 4, 4: 3, 5: 4, 6: 6, 7: 2, 8: 4, 9: 3, 10: 5, 11: 1, 12: 3, 13: 2, 14: 4, 15: 6, 16: 5, 17: 1, 18: 5, 19: 5, 20: 1, 21: 1, 22: 1, 23: 4}
# 13: Thinness: 7
# Order: [13, 14, 6, 15, 16, 17, 10, 18, 19, 7, 20, 12, 9, 8, 21, 22, 23, 11, 24, 0, 4, 3, 25, 2, 5, 1]
# Partition: {0: 6, 1: 7, 2: 1, 3: 2, 4: 5, 5: 7, 6: 6, 7: 5, 8: 7, 9: 3, 10: 1, 11: 4, 12: 2, 13: 6, 14: 3, 15: 5, 16: 2, 17: 7, 18: 4, 19: 4, 20: 4, 21: 4, 22: 4, 23: 4, 24: 2, 25: 3}
# 14: Thinness: 7
# Order: [14, 15, 12, 16, 17, 18, 10, 19, 5, 2, 7, 20, 6, 0, 3, 1, 11, 8, 21, 9, 4, 22, 23, 24, 25, 26, 13, 27]
# Partition: {0: 1, 1: 7, 2: 7, 3: 5, 4: 7, 5: 1, 6: 1, 7: 5, 8: 6, 9: 4, 10: 7, 11: 2, 12: 1, 13: 3, 14: 7, 15: 1, 16: 6, 17: 5, 18: 3, 19: 4, 20: 2, 21: 3, 22: 3, 23: 3, 24: 3, 25: 3, 26: 3, 27: 1}
# 15: Thinness: 8
# Order: [15, 16, 17, 18, 19, 20, 7, 21, 22, 8, 6, 12, 11, 23, 10, 3, 1, 4, 2, 5, 0, 9, 24, 25, 26, 14, 27, 13, 28, 29]
# Partition: {0: 2, 1: 7, 2: 7, 3: 5, 4: 3, 5: 3, 6: 2, 7: 7, 8: 2, 9: 8, 10: 5, 11: 4, 12: 3, 13: 1, 14: 6, 15: 4, 16: 1, 17: 6, 18: 7, 19: 8, 20: 5, 21: 2, 22: 1, 23: 1, 24: 6, 25: 6, 26: 6, 27: 1, 28: 6, 29: 8}
# 16: Thinness: 8
# Order: [16, 17, 18, 13, 10, 9, 19, 8, 2, 20, 21, 1, 22, 3, 23, 24, 25, 11, 26, 27, 12, 28, 4, 0, 29, 14, 30, 6, 5, 15, 7, 31]
# Partition: {0: 1, 1: 2, 2: 7, 3: 5, 4: 2, 5: 3, 6: 3, 7: 8, 8: 7, 9: 6, 10: 5, 11: 1, 12: 3, 13: 2, 14: 4, 15: 8, 16: 6, 17: 5, 18: 2, 19: 7, 20: 8, 21: 3, 22: 1, 23: 4, 24: 4, 25: 1, 26: 8, 27: 4, 28: 8, 29: 4, 30: 8, 31: 2}
# 17: Thinness: 9
# Order: [17, 8, 18, 19, 20, 21, 22, 0, 23, 24, 9, 15, 25, 10, 26, 12, 27, 11, 28, 14, 13, 29, 30, 7, 5, 31, 16, 1, 2, 4, 6, 32, 3, 33]
# Partition: {0: 2, 1: 2, 2: 9, 3: 8, 4: 9, 5: 7, 6: 2, 7: 7, 8: 2, 9: 9, 10: 6, 11: 8, 12: 5, 13: 1, 14: 7, 15: 4, 16: 3, 17: 4, 18: 3, 19: 6, 20: 1, 21: 5, 22: 9, 23: 8, 24: 7, 25: 1, 26: 5, 27: 3, 28: 3, 29: 3, 30: 3, 31: 3, 32: 3, 33: 6}
# 18: Thinness: 9
# Order: [18, 19, 20, 21, 22, 15, 23, 10, 4, 24, 14, 5, 11, 25, 26, 9, 27, 28, 29, 2, 12, 7, 13, 3, 30, 31, 32, 33, 6, 0, 16, 8, 1, 17, 34, 35]
# Partition: {0: 9, 1: 9, 2: 9, 3: 3, 4: 5, 5: 5, 6: 6, 7: 1, 8: 6, 9: 9, 10: 1, 11: 4, 12: 6, 13: 2, 14: 3, 15: 5, 16: 8, 17: 7, 18: 6, 19: 5, 20: 4, 21: 3, 22: 9, 23: 1, 24: 2, 25: 8, 26: 7, 27: 6, 28: 2, 29: 2, 30: 8, 31: 8, 32: 7, 33: 8, 34: 7, 35: 3}
# 19: Thinness: 10
# Order: [19, 20, 21, 17, 22, 23, 24, 16, 0, 25, 26, 27, 9, 10, 12, 14, 28, 15, 8, 5, 13, 29, 2, 11, 4, 7, 30, 3, 6, 1, 31, 32, 33, 34, 35, 36, 18, 37]
# Partition: {0: 1, 1: 6, 2: 1, 3: 3, 4: 5, 5: 7, 6: 3, 7: 5, 8: 3, 9: 3, 10: 6, 11: 8, 12: 5, 13: 2, 14: 9, 15: 10, 16: 7, 17: 1, 18: 4, 19: 9, 20: 10, 21: 7, 22: 6, 23: 2, 24: 4, 25: 3, 26: 8, 27: 5, 28: 8, 29: 8, 30: 4, 31: 4, 32: 4, 33: 4, 34: 4, 35: 4, 36: 4, 37: 3}
def check_thinness_of_Kn_by_Knc():
    for i in range(2, 20, 2):
        solver = Z3ThinnessSolver(2*i)
        # add_left_order_constraints(solver, i)
        # add_2_per_side_in_each_class_constraints(solver, i)
        # add_right_pair_orders_constraints(solver, i)
        # add_cyclic_classes_constraints(solver, i)

        # add_left_consecutive_constraint(solver, i)

        lower_bound = ceil(i / 2)
        solution = solver.solve(create_Kn_by_Knc(i), lower_bound=lower_bound, upper_bound=lower_bound, partial_orders=[heuristic_order_for_Kn_by_Knc4(i)], partial_classes=partition_for_heuristic_4(i))
        print(f"{i}: {solution}")


def add_left_consecutive_constraint(solver: Z3ThinnessSolver, vertices_per_side: int):
    optimize = solver.solver
    orders = solver.variables.orders
    for i in range(vertices_per_side):
        optimize.add(orders[i] +1 == orders[i + 1])


def add_cyclic_classes_constraints(solver: Z3ThinnessSolver, vertices_per_side: int):
    optimize = solver.solver
    classes = solver.variables.classes
    optimize.add(classes[0] == classes[vertices_per_side * 2 - 1])
    for i in range(2, vertices_per_side, 2):
        optimize.add(classes[i] == classes[i - 2 + vertices_per_side])
    

def add_cyclic_order_constraints(solver: Z3ThinnessSolver, vertices_per_side: int):
    optimize = solver.solver
    orders = solver.variables.orders
    optimize.add(orders[0] > orders[vertices_per_side * 2 - 1])
    optimize.add(orders[1] < orders[vertices_per_side * 2 - 2])
    for i in range(2, vertices_per_side, 2):
        optimize.add(orders[i + vertices_per_side - 1] < orders[i])
        optimize.add(orders[i + 1] < orders[i + vertices_per_side - 2])


def add_right_pair_orders_constraints(solver: Z3ThinnessSolver, vertices_per_side: int):
    optimize = solver.solver
    orders = solver.variables.orders
    for i in range(0, vertices_per_side, 2):
        optimize.add(orders[i + vertices_per_side] > orders[i + vertices_per_side + 1])


def add_2_per_side_in_each_class_constraints(solver: Z3ThinnessSolver, vertices_per_side: int):
    optimize = solver.solver
    classes = solver.variables.classes
    for i in range(0, vertices_per_side, 2):
        optimize.add(classes[i] == classes[i + 1])
        optimize.add(classes[i] == i/2+1)
        optimize.add(classes[i+vertices_per_side] == classes[i + vertices_per_side + 1])
        for j in range(i+2, vertices_per_side, 2):
            optimize.add(classes[i] != classes[j])
            optimize.add(classes[i+vertices_per_side] != classes[j + vertices_per_side])


def add_joined_each_4_constraints(solver: Z3ThinnessSolver, vertices_per_side: int):
    optimize = solver.solver
    classes = solver.variables.classes
    for i in range(0, vertices_per_side, 2):
        optimize.add(classes[i] == classes[i + 1])
        optimize.add(classes[i] == classes[i + vertices_per_side])
        optimize.add(classes[i] == classes[i + vertices_per_side + 1])


def add_ordered_littles_constraints(solver: Z3ThinnessSolver, vertices_per_side: int):
    little_vertices_right = floor(vertices_per_side / 2)
    optimize = solver.solver
    for i in range(little_vertices_right):
        optimize.add(solver.variables.orders[i] > solver.variables.orders[i + vertices_per_side])

    for i in range(little_vertices_right, vertices_per_side):
        optimize.add(solver.variables.orders[i] < solver.variables.orders[i + vertices_per_side])


def add_interleaved_littles_constraints(solver: Z3ThinnessSolver, vertices_per_side: int):
    optimize = solver.solver
    orders = solver.variables.orders
    for i in range(0, vertices_per_side, 2):
        optimize.add(orders[i] < orders[i + vertices_per_side])

    for i in range(1, vertices_per_side, 2):
        optimize.add(orders[i] > orders[i + vertices_per_side])


def add_left_order_constraints(solver: Z3ThinnessSolver, vertices_per_side: int):
    optimize = solver.solver
    for i in range(vertices_per_side - 1):
        optimize.add(solver.variables.orders[i] < solver.variables.orders[i + 1]) 


def add_right_order_constraints(solver: Z3ThinnessSolver, vertices_per_side: int):
    optimize = solver.solver
    for i in range(vertices_per_side - 1):
        optimize.add(solver.variables.orders[i + vertices_per_side] < solver.variables.orders[i + 1 + vertices_per_side]) 


def try_heuristic_orders_for_Kn_by_Knc():
    for i in range(2, 20, 2):
        print(f"{i}:", end=" ", flush=True)
        graph = create_Kn_by_Knc(i)
        expected_thinness = ceil(i / 2.0)
        order = heuristic_order_for_Kn_by_Knc4(i)
        partition = minimum_partition_for_vertex_order(graph, order)
        print(order, partition)
        assert expected_thinness == len(partition), f"Expected thinness: {expected_thinness}, actual: {len(partition)}, partition: {partition}, order: {order}"


def partition_for_heuristic_4(vertices_per_side: int):
    parts = floor(vertices_per_side / 2)
    partition = [set() for _ in range(parts)]
    for part, vertex in enumerate(range(vertices_per_side+1, 2*vertices_per_side, 2)):
        partition[part].add(vertex)
    for part, vertex in enumerate(range(0, vertices_per_side, 2)):
        partition[part].add(vertex)
        partition[part].add(vertex+1)
    partition[0].add(vertices_per_side*2-2)
    for part, vertex in enumerate(range(vertices_per_side, 2*vertices_per_side - 2, 2), start=1):
        partition[part].add(vertex)
    return partition


def heuristic_order_for_Kn_by_Knc4(vertices_per_side: int):
    order = []
    order.extend(range(vertices_per_side*2-1, vertices_per_side-1, -2))
    for i in range(0, vertices_per_side, 2):
        order += [i, i+1, i+vertices_per_side]
    return order


def heuristic_order_for_Kn_by_Knc3(vertices_per_side: int):
    order = []
    order.extend(range(vertices_per_side*2-1, vertices_per_side-1, -2))
    order.extend(range(vertices_per_side-2, -1, -2))
    order.extend(range(vertices_per_side, 2*vertices_per_side, 2))
    order.extend(range(1, vertices_per_side, 2))
    return order


def heuristic_order_for_Kn_by_Knc2(vertices_per_side: int):
    order = []
    for i in range(0, vertices_per_side, 2):
        order += [i+vertices_per_side+1, i, i+1, i+vertices_per_side]
    return order


def heuristic_order_for_Kn_by_Knc1(vertices_per_side: int):
    order = []
    impares = range(1, vertices_per_side, 2)
    for i in impares:
        order.append(i - 1 + vertices_per_side)
        order.append(i)
    pares_reverse = reversed(range(2, vertices_per_side, 2))
    for i in pares_reverse:
        order.append(i + vertices_per_side + 1)
        order.append(i)
    order += [0, vertices_per_side + 1]
    return order


# try_heuristic_orders_for_Kn_by_Knc()
check_thinness_of_Kn_by_Knc()
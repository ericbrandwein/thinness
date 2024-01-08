import itertools
from z3 import *
from .consistent_solution import ConsistentSolution

K_THIN_VAR_NAME = 'k_thin'

class Variables:
    def __init__(self, number_of_vertices):
        self.k_thin = Int(K_THIN_VAR_NAME)
        self.classes = {node: Int(self._class_var_name(node)) for node in range(number_of_vertices)}
        self.orders = {node: Int(self._order_var_name(node)) for node in range(number_of_vertices)}

    @staticmethod
    def _class_var_name(node):
        return f'class_{node}'

    @staticmethod
    def _order_var_name(node):
        return f'order_{node}'
    

class Z3ParameterSolver:
    def __init__(self, number_of_vertices):
        self.solver = Optimize()
        self.variables = Variables(number_of_vertices)
        self._add_classes_constraints()
        self._add_order_constraints()
        self.solver.minimize(self.variables.k_thin)

    def solve(self, graph, lower_bound=1, upper_bound=None, partial_orders=[], partial_classes=[]):
        number_of_vertices = len(self.variables.classes)
        if graph.order() != number_of_vertices:
            raise ValueError(f'The number of vertices of the graph must match the number of vertices defined when initializing the solver.\nGraph order: {graph.order()}\nSolver order: {number_of_vertices}')
        self.solver.push()
        self._add_bounds_constraint(lower_bound, upper_bound)
        self._add_consistency_constraints(graph)
        self._add_partial_orders_constraints(partial_orders)
        self._add_partial_classes_constraints(partial_classes)
        
        solution = None
        if self.solver.check() == sat:
            solution = self._build_solution()
        self.solver.pop()
        return solution

    def _add_classes_constraints(self):
        for partition_class in self.variables.classes.values():
            self.solver.add(partition_class > 0, partition_class <= self.variables.k_thin)

    def _add_order_constraints(self):
        for order in self.variables.orders.values():
            self.solver.add(order > 0, order <= len(self.variables.orders))
        for some_order, other_order in itertools.combinations(self.variables.orders.values(), 2):
            self.solver.add(some_order != other_order)

    def _add_bounds_constraint(self, lower_bound, upper_bound):
        self.solver.add(self.variables.k_thin >= lower_bound, self.variables.k_thin <= upper_bound)

    def _add_consistency_constraints(self, graph):
        for u, v, w in itertools.permutations(graph.vertices(), 3):
            if graph.has_edge(u, w) and not graph.has_edge(v, w):
                self.solver.add(self.build_consistency_constraint(u, v, w))

    def _add_partial_orders_constraints(self, partial_orders: list[list]):
        for partial_order in partial_orders:
            for u, v in itertools.pairwise(partial_order):
                self.solver.add(self.variables.orders[u] < self.variables.orders[v])
    
    def _add_partial_classes_constraints(self, partial_classes: list[set]):
        for partial_class in partial_classes:
            for u, v in itertools.pairwise(partial_class):
                self.solver.add(self.variables.classes[u] == self.variables.classes[v])

    def _build_solution(self) -> ConsistentSolution:
        return ConsistentSolution(self._build_order(), self._build_partition())

    def _build_order(self):
        return sorted(self.variables.orders, key=lambda node: self.solver.model()[self.variables.orders[node]].as_long())

    def _build_partition(self):
        model = self.solver.model()
        thinness = model[self.variables.k_thin].as_long()
        partition = [set() for _ in range(thinness)]
        for node, part in self.variables.classes.items():
            partition[model[part].as_long() - 1].add(node)
        return partition

    def build_consistency_constraint(self, u, v, w):
        raise NotImplementedError()


class Z3ThinnessSolver(Z3ParameterSolver):
    def __init__(self, number_of_vertices):
        super().__init__(number_of_vertices)

    def solve(self, graph, lower_bound=1, upper_bound=None, partial_orders=[], partial_classes=[]):
        return super().solve(graph, lower_bound, max(1, upper_bound or graph.order() - 1), partial_orders, partial_classes)

    def build_consistency_constraint(self, u, v, w):
        # u, v and w cannot be ordered and u, v in the same class
        return Or(
            self.variables.orders[w] < self.variables.orders[v],
            self.variables.orders[v] < self.variables.orders[u],
            self.variables.classes[u] != self.variables.classes[v]
        )


class Z3ProperThinnessSolver(Z3ParameterSolver):
    def __init__(self, number_of_vertices):
        super().__init__(number_of_vertices)

    def solve(self, graph, lower_bound=1, upper_bound=None, partial_orders=[], partial_classes=[]):
        return super().solve(graph, lower_bound, upper_bound or graph.order() - 1, partial_orders, partial_classes)

    def build_consistency_constraint(self, u, v, w):
        # It cannot happen that u, v in the same class and (u < v < w or w < v < u)
        return Or(
            self.variables.classes[u] != self.variables.classes[v],
            And(
                self.variables.orders[v] < self.variables.orders[u],
                self.variables.orders[v] < self.variables.orders[w]
            ),
            And(
                self.variables.orders[v] > self.variables.orders[u],
                self.variables.orders[v] > self.variables.orders[w]
            )
        ) 

import itertools

from z3 import *


K_THIN_VAR_NAME = 'k_thin'


class ConsistentSolution:
    def __init__(self, order, partition) -> None:
        self.order = order
        self.partition = partition
        self.thinness = len(set(partition.values()))

    @staticmethod
    def from_model(model, variables):
        order = sorted(variables.orders, key=lambda node: model[variables.orders[node]].as_long())
        partition = {
            node: model[var].as_long()
            for node, var in variables.classes.items()
        }
        return ConsistentSolution(order, partition)


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

    def solve(self, graph, lower_bound=1, upper_bound=None):
        self.solver.push()
        self._add_bounds_constraint(lower_bound, upper_bound)
        self._add_consistency_constraints(graph)
        
        solution = None
        if self.solver.check() == sat:
            solution = ConsistentSolution.from_model(self.solver.model(), self.variables)
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
    
    def build_consistency_constraint(self, u, v, w):
        raise NotImplementedError()


class Z3ThinnessSolver(Z3ParameterSolver):
    def __init__(self, number_of_vertices):
        super().__init__(number_of_vertices)

    def solve(self, graph, lower_bound=1, upper_bound=None):
        return super().solve(graph, lower_bound, upper_bound or graph.order() / 2)

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

    def solve(self, graph, lower_bound=1, upper_bound=None):
        return super().solve(graph, lower_bound, upper_bound or graph.order() - 1)

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

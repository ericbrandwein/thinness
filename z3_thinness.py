import itertools

from z3 import *


K_THIN_VAR_NAME = 'k_thin'

class Variables:
    def __init__(self, graph):
        self.k_thin = Int(K_THIN_VAR_NAME)
        self.classes = {node: Int(self._class_var_name(node)) for node in graph.vertices()}
        self.orders = {node: Int(self._order_var_name(node)) for node in graph.vertices()}

    @staticmethod
    def _class_var_name(node):
        return f'class_{node}'

    @staticmethod
    def _order_var_name(node):
        return f'order_{node}'


def _add_constraints(solver, graph, variables, lower_bound, upper_bound):
    # Target
    solver.add(variables.k_thin >= lower_bound, variables.k_thin <= upper_bound)

    # Classes
    for partition_class in variables.classes.values():
        solver.add(partition_class > 0, partition_class <= variables.k_thin)

    # Order
    for order in variables.orders.values():
        solver.add(order > 0, order <= len(graph.vertices()))
    for some_order, other_order in itertools.combinations(variables.orders.values(), 2):
        solver.add(some_order != other_order)

    # Consistency
    for u, v, w in itertools.permutations(graph.vertices(), 3):
        if graph.has_edge(u, w) and not graph.has_edge(v, w):
            # u, v and w cannot be ordered and u, v in the same class
            solver.add(
                Or(
                    variables.orders[w] < variables.orders[v],
                    variables.orders[v] < variables.orders[u],
                    variables.classes[u] != variables.classes[v]
                )
            )


def _get_order(model, variables):
    return sorted(variables.orders, key=lambda node: model[variables.orders[node]].as_long())


def _get_partition(model, variables):
    return {
        node: model[var].as_long()
        for node, var in variables.classes.items()
    }


def _create_solution(model, variables):
    order = _get_order(model, variables)
    partition = _get_partition(model, variables)
    return len(set(partition.values())), order, partition


def calculate_thinness_with_z3(graph, lower_bound=1, upper_bound=None):
    opt = Optimize()
    upper_bound = upper_bound or len(graph.vertices()) / 2
    
    variables = Variables(graph)
    _add_constraints(opt, graph, variables, lower_bound, upper_bound)
    opt.minimize(variables.k_thin)

    if opt.check() == sat:
        return _create_solution(opt.model(), variables)
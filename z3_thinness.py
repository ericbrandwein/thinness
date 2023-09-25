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


def _thinness_consistency_constraint(variables, u, v, w):
    # u, v and w cannot be ordered and u, v in the same class
    return Or(
        variables.orders[w] < variables.orders[v],
        variables.orders[v] < variables.orders[u],
        variables.classes[u] != variables.classes[v]
    )


def _proper_thinness_consistency_constraint(variables, u, v, w):
    # It cannot happen that u, v in the same class and (u < v < w or w < v < u)
    return Or(
        variables.classes[u] != variables.classes[v],
        And(
            variables.orders[v] < variables.orders[u],
            variables.orders[v] < variables.orders[w]
        ),
        And(
            variables.orders[v] > variables.orders[u],
            variables.orders[v] > variables.orders[w]
        )
    )


def _add_bounds_constraint(solver, variables, lower_bound, upper_bound):
    solver.add(variables.k_thin >= lower_bound, variables.k_thin <= upper_bound)


def _add_classes_constraints(solver, variables):
    for partition_class in variables.classes.values():
        solver.add(partition_class > 0, partition_class <= variables.k_thin)


def _add_order_constraints(solver, variables, graph):
    for order in variables.orders.values():
        solver.add(order > 0, order <= len(graph.vertices()))
    for some_order, other_order in itertools.combinations(variables.orders.values(), 2):
        solver.add(some_order != other_order)


def _add_consistency_constraints(solver, variables, graph, build_consistency_constraint):
    for u, v, w in itertools.permutations(graph.vertices(), 3):
        if graph.has_edge(u, w) and not graph.has_edge(v, w):
            solver.add(build_consistency_constraint(variables, u, v, w))


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


def _calculate_with_z3(graph, consistency_func, lower_bound, upper_bound):
    opt = Optimize()
    
    variables = Variables(graph)
    _add_bounds_constraint(opt, variables, lower_bound, upper_bound)
    _add_classes_constraints(opt, variables)
    _add_order_constraints(opt, variables, graph)
    _add_consistency_constraints(opt, variables, graph, consistency_func)
    opt.minimize(variables.k_thin)

    if opt.check() == sat:
        return _create_solution(opt.model(), variables)


def calculate_thinness_with_z3(graph, lower_bound=1, upper_bound=None):
    return _calculate_with_z3(
        graph, 
        _thinness_consistency_constraint, 
        lower_bound, 
        upper_bound or graph.order() / 2
    )


def calculate_proper_thinness_with_z3(graph, lower_bound=1, upper_bound=None):
    return _calculate_with_z3(
        graph, 
        _proper_thinness_consistency_constraint, 
        lower_bound,
        upper_bound or graph.order() - 1
    )

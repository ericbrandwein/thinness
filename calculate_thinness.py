import networkx as nx
import sys
from graph_reader import read_graph

GRAPHS_DIR = "adjlists"
GRAPHS_FILE_EXTENSION = ".adjlist"


class ConsistentSolution:
    def __init__(self, ordering, partition):
        self.ordering = ordering
        self.partition = partition

    @property
    def number_of_classes(self):
        return len(set(self.partition.values()))
    
    @property
    def complete_partition(self):
        return {
            node: self.partition[node] if node in self.partition else 0 
            for node in self.ordering
        }
    
    def __str__(self) -> str:
        return "\n".join([
            f"Thinness: {self.number_of_classes}", 
            f"Ordering: {self.ordering}", 
            f"Partition: {self.complete_partition}"
        ])



def _find_first_adjacent(G, nodes, node):
    return next(
        (index for index, adjacent in enumerate(nodes) if G.has_edge(adjacent, node)), 
        None
    )


def _add_last_constraints(G, constraints_graph, before, new_node):
    for u_index, u in enumerate(before):
        if G.has_edge(u, new_node):
            for v in before[u_index + 1:]:
                if not G.has_edge(v, new_node):
                    constraints_graph.add_edge(u, v)


def _add_middle_constraints(G, constraints_graph, before, after, new_node):
    nonadjacent_after = [
        nonadjacent for nonadjacent in after if not G.has_edge(new_node, nonadjacent)
    ]
    for u in before:
        if _find_first_adjacent(G, nonadjacent_after, u) is not None:
            constraints_graph.add_edge(u, new_node)
         

def _add_first_constraints(G, constraints_graph, after, new_node):
    for v_index, v in enumerate(after):
        nonadjacent_v = [
            nonadjacent for nonadjacent in after[v_index + 1:] if not G.has_edge(v, nonadjacent)
        ]
        if _find_first_adjacent(G, nonadjacent_v, new_node) is not None:
            constraints_graph.add_edge(new_node, v)


def _add_constraints(G, constraints_graph, before, after, new_node):
    _add_last_constraints(G, constraints_graph, before, new_node)
    _add_middle_constraints(G, constraints_graph, before, after, new_node)
    _add_first_constraints(G, constraints_graph, after, new_node)


def _extend_constraints_graph(G, constraints_graph, ordering, new_node):
    new_graph = constraints_graph.copy()
    position = ordering.index(new_node)
    before = ordering[:position]
    after = ordering[position + 1:]
    _add_constraints(G, new_graph, before, after, new_node)
    return new_graph


def _cocomparability_coloring(graph):
    return nx.coloring.greedy_color(graph)


def _calculate_thinness_for_ordering(G, constraints_graph, ordering, new_node):
    constraints_graph = _extend_constraints_graph(G, constraints_graph, ordering, new_node)
    coloring = _cocomparability_coloring(constraints_graph)
    return coloring, constraints_graph


def insertions(iterable, element):
    for i in range(len(iterable) + 1):
        yield iterable[:i] + [element] + iterable[i:]


def _calculate_thinness_for_strict_suborder(G, constraints_graph, ordering, remaining_nodes, lower_bound: int, upper_bound: int) -> ConsistentSolution | None:
    best_solution = None
    next_node = remaining_nodes.pop()
    for new_ordering in insertions(ordering, next_node):
        solution = _calculate_thinness_for_suborder(
            G, constraints_graph, new_ordering, next_node, remaining_nodes, lower_bound, upper_bound
        )
        if solution:
            new_thinness = solution.number_of_classes
            if new_thinness < upper_bound:
                upper_bound = new_thinness
                best_solution = solution
            if upper_bound <= lower_bound:
                break
    remaining_nodes.add(next_node)
    return best_solution


def _calculate_thinness_for_suborder(G, constraints_graph, ordering, new_node, remaining_nodes, lower_bound: int, upper_bound: int) -> ConsistentSolution | None:
    subG = nx.induced_subgraph(G, ordering)
    best_partition, constraints_graph = _calculate_thinness_for_ordering(
        subG, constraints_graph, ordering, new_node
    )
    best_solution = ConsistentSolution(ordering, best_partition)
    thinness = best_solution.number_of_classes
    if thinness >= upper_bound:
        return None
    if len(remaining_nodes) == 0:
        return best_solution
    
    return _calculate_thinness_for_strict_suborder(G, constraints_graph, ordering, remaining_nodes, lower_bound, upper_bound)


def calculate_thinness_backtracking(G, lower_bound=1, upper_bound=None):
    nodes = set(G.nodes())
    ordering = [nodes.pop()]
    return _calculate_thinness_for_suborder(
        G, nx.Graph(), ordering, ordering[0], nodes, lower_bound,
        upper_bound or max(1, G.number_of_nodes() - 1)
    )


def calculate_thinness(G, lower_bound=None, upper_bound=None):
    return calculate_thinness_backtracking(G, lower_bound, upper_bound)


def _parse_arguments():
    if len(sys.argv) < 2:
        return "graph"
    else:
        return sys.argv[1]


def _main():
    graph_file = _parse_arguments()
    G = read_graph(graph_file)
    solution = calculate_thinness_backtracking(G)
    if solution:
        print(solution)
    else:
        print("No solution found")


if __name__ == "__main__":
    _main()
    

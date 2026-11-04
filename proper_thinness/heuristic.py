from sage.graphs.graph import Graph
from sage.graphs.base.boost_graph import bandwidth_heuristics
from sage.graphs.graph_decompositions.vertex_separation import vertex_separation

from thinness.consistent_solution import ConsistentSolution


def heuristic_solution(graph: Graph, extra_orders: list[list] = ()) -> ConsistentSolution:
    """A solution for the proper thinness of `graph`, the best one for a few vertex orders.

    Those are the orders in `extra_orders` and some where neighbors tend to be close.
    """
    orders = [*extra_orders, *_candidate_orders(graph)]
    solutions = [solution_from_order(graph, order) for order in orders]
    return min(solutions, key=lambda solution: solution.thinness)


def _candidate_orders(graph: Graph):
    """Orders where neighbors tend to be close, which tend to have few conflicts.

    Reversing an order gives the same conflicts, so reversed orders are not tried.
    """
    _, order = vertex_separation(graph)
    yield order
    for algorithm in ['cuthill_mckee', 'king']:
        _, order = bandwidth_heuristics(graph, algorithm=algorithm)
        yield order


def solution_from_order(graph: Graph, order: list) -> ConsistentSolution:
    """An optimal partition for the proper thinness of `graph` consistent with `order`.

    Two vertices conflict if they can't be in the same part with this order. A
    partition is consistent with the order if and only if no two vertices of a
    part conflict, so it is an optimal coloring of the conflicts.
    """
    conflicts = _conflicts(graph, order)
    part_of_position = _partition_into_chains(conflicts)
    partition = [set() for _ in range(max(part_of_position, default=-1) + 1)]
    for position, part in enumerate(part_of_position):
        partition[part].add(order[position])
    return ConsistentSolution(list(order), partition)


def _conflicts(graph: Graph, order: list) -> list[int]:
    """For each position, the positions it conflicts with, as a bitmask.

    The vertices at positions i < j conflict if some vertex after j is adjacent to
    the one at i but not to the one at j, or some vertex before i is adjacent to
    the one at j but not to the one at i.
    """
    n = len(order)
    position_of = {vertex: position for position, vertex in enumerate(order)}
    neighbors = [0] * n
    for u, v in graph.edge_iterator(labels=False):
        neighbors[position_of[u]] |= 1 << position_of[v]
        neighbors[position_of[v]] |= 1 << position_of[u]

    conflicts = [0] * n
    for i in range(n):
        before_i = (1 << i) - 1
        for j in range(i + 1, n):
            after_j = ~((1 << (j + 1)) - 1)
            if (
                neighbors[i] & ~neighbors[j] & after_j
                or neighbors[j] & ~neighbors[i] & before_i
            ):
                conflicts[i] |= 1 << j
                conflicts[j] |= 1 << i
    return conflicts


def _partition_into_chains(conflicts: list[int]) -> list[int]:
    """Optimal coloring of the conflicts, as the part of each position.

    The conflicts graph is a cocomparability graph: orienting the pairs that
    don't conflict from the earlier position to the later one gives a transitive
    orientation. So an optimal coloring is a minimum partition of that order into
    chains, which by Dilworth's theorem has as many chains as positions minus the
    size of a maximum matching between earlier and later positions.
    """
    n = len(conflicts)
    previous = [-1] * n

    def augment(position: int, visited: list[bool]) -> bool:
        for next_position in range(position + 1, n):
            if not conflicts[position] >> next_position & 1 and not visited[next_position]:
                visited[next_position] = True
                if previous[next_position] == -1 or augment(previous[next_position], visited):
                    previous[next_position] = position
                    return True
        return False

    for position in range(n):
        augment(position, [False] * n)

    following = [-1] * n
    for position in range(n):
        if previous[position] != -1:
            following[previous[position]] = position
    part_of_position = [-1] * n
    parts = 0
    for position in range(n):
        if previous[position] == -1:
            chain_position = position
            while chain_position != -1:
                part_of_position[chain_position] = parts
                chain_position = following[chain_position]
            parts += 1
    return part_of_position

from collections import deque

from sage.graphs.graph import Graph

from .consistent_solution import ConsistentSolution


def solution_from_vertex_separation(graph: Graph, linear_layout: list[int], vertex_separation: int) -> ConsistentSolution:
    """The vertices in `graph` must be numbers from 0 to `graph.order() - 1`."""
    last_neighbors = _get_last_neighbors(graph, linear_layout)
    order = deque()
    part_of = [None] * graph.order()
    is_active = [False] * graph.order()
    for index, vertex in enumerate(linear_layout):
        for neighbor in graph.neighbors(vertex):
            if last_neighbors[neighbor] == index:
                is_active[neighbor] = False
        if last_neighbors[vertex] > index:
            # Active vertex
            order.append(vertex)
            active_vertices = [active_vertex for active_vertex in graph if is_active[active_vertex]]
            part_of[vertex] = _mex(part_of[active_vertex] for active_vertex in active_vertices)
            is_active[vertex] = True
        else:
            # Inactive vertex
            position_of_last_neighbor_in_layout = last_neighbors[vertex]
            if position_of_last_neighbor_in_layout == 0:
                order.appendleft(vertex)
                part_of[vertex] = 0
            else:
                last_neighbor = linear_layout[position_of_last_neighbor_in_layout]
                _insert_before(order, vertex, last_neighbor)
                part_of[vertex] = part_of[last_neighbor]

    partition = [set() for _ in set(part_of)]
    for vertex, part in enumerate(part_of):
        partition[part].add(vertex)

    return ConsistentSolution(order, partition)


def _get_last_neighbors(graph: Graph, linear_layout: list[int]) -> list[int]:
    """Return the position of the last neighbor of each vertex in the linear layout."""
    last_neighbors = [0] * graph.order()
    for index, vertex in enumerate(linear_layout):
        for neighbor in graph.neighbors(vertex):
            last_neighbors[neighbor] = max(index, last_neighbors[neighbor])

    return last_neighbors


def _mex(iterable) -> int:
    """Return the minimum excluded integer."""
    sorted_iterable = sorted(iterable)
    for i, element in enumerate(sorted_iterable):
        if i != element:
            return i

    return len(sorted_iterable)


def _insert_before(deck: deque, element, before):
    position_of_last_neighbor_in_order = deck.index(before)
    deck.insert(position_of_last_neighbor_in_order, element)
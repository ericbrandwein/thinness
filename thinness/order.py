import itertools

from sage.graphs.graph import Graph, DiGraph

from .compatibility import build_compatibility_graph


def thinness_of_order(graph: Graph, order: list[int]) -> int:
    global graph6_string
    graph6_string = graph.graph6_string() 
    return thinness_from_compatibility_graph(build_compatibility_graph(graph, order), order)


def thinness_from_compatibility_graph(compatibility_graph: Graph, order: list[int]) -> int:
    transitive_orientation = _build_transitive_orientation(compatibility_graph.complement(), order)
    source = _add_source(transitive_orientation)
    sink = _add_sink(transitive_orientation)
    return min_flow(transitive_orientation, source, sink)


def min_flow(transitive_orientation: DiGraph, source: int, sink: int) -> int:
    global graph6_string
    network = _build_min_edge_flow_network(transitive_orientation, source, sink)
    feasible_flow = _build_feasible_flow(network, source, sink)
    assert _is_valid_flow(network, source, sink, feasible_flow)
    feasible_flow_value = sum(feasible_flow.edge_label(source, neighbor) for neighbor in feasible_flow.neighbor_out_iterator(source))
    residual = _make_residual_network(network, feasible_flow, feasible_flow_value)
    max_flow_value = residual.flow(sink, source, use_edge_labels=True)
    return feasible_flow_value - max_flow_value


def _make_residual_network(network: DiGraph, feasible_flow: DiGraph, capacity: int) -> DiGraph:
    residual = DiGraph()
    for u, v, label in feasible_flow.edges():
        residual.add_edge(u, v, capacity - label)
        residual.add_edge(v, u, label - network.edge_label(u, v))
    return residual
    

def _is_valid_flow(graph: DiGraph, source: int, sink: int, flow: DiGraph) -> bool:
    for u, v, label in graph.edges():
        if flow.edge_label(u, v) < label:
            return False
    return _keeps_flow(graph, source, sink, flow)


def _keeps_flow(graph: DiGraph, source: int, sink: int, flow: DiGraph) -> bool:
    for vertex in graph.vertex_iterator():
        if vertex != source and vertex != sink:
            if sum(flow.edge_label(neighbor, vertex) for neighbor in flow.neighbors_in(vertex)) != \
                    sum(flow.edge_label(vertex, neighbor) for neighbor in flow.neighbors_out(vertex)):
                return False
    return True


def _build_min_edge_flow_network(transitive_orientation: DiGraph, source: int, sink: int) -> DiGraph:
    network = DiGraph()
    network.add_vertices([source, sink])
    for vertex in transitive_orientation.vertex_iterator():
        if vertex not in [source, sink]:
            network.add_vertex(f'{vertex}_in')
            network.add_vertex(f'{vertex}_out')
            network.add_edge(f'{vertex}_in', f'{vertex}_out', 1)
    for u, v in transitive_orientation.edges(labels=False):
        if u == source:
            network.add_edge(source, f'{v}_in', 0)
        elif v == sink:
            network.add_edge(f'{u}_out', sink, 0)
        else:
            network.add_edge(f'{u}_out', f'{v}_in', 0)
    return network


def _build_transitive_orientation(graph: Graph, order: list[int]) -> Graph:
    transitive_orientation = DiGraph(graph.order())
    for u, v in graph.edges(labels=False):
        if order.index(u) < order.index(v):
            transitive_orientation.add_edge(u, v)
        else:
            transitive_orientation.add_edge(v, u)
    return transitive_orientation


def _add_source(transitive_orientation: DiGraph) -> int:
    source = transitive_orientation.add_vertex()
    transitive_orientation.add_edges((source, vertex) for vertex in transitive_orientation.sources() if vertex != source)
    return source


def _add_sink(transitive_orientation: DiGraph) -> int:
    sink = transitive_orientation.add_vertex()
    transitive_orientation.add_edges((vertex, sink) for vertex in transitive_orientation.sinks() if vertex != sink)
    return sink


def _build_feasible_flow(network: DiGraph, source: int, sink: int) -> DiGraph:
    flow = network.copy()
    for u, v in flow.edges(labels=False):
        flow.set_edge_label(u, v, 0)
    path = _search_magnifying_path(network, flow, source, sink)
    while path is not None:
        for u, v in itertools.pairwise(path):
            flow.set_edge_label(u, v, flow.edge_label(u, v) + 1)
        path = _search_magnifying_path(network, flow, source, sink)
    return flow


def _search_magnifying_path(network: DiGraph, flow: DiGraph, source: int, sink: int) -> list[int]:
    path = _search_zero_edge_path(network, flow, source, sink)
    if path is not None:
        last = path[-1]
        while last != sink:
            last = next(flow.neighbor_out_iterator(last))
            path.append(last)
    return path


def _search_zero_edge_path(network: DiGraph, flow: DiGraph, source: int, sink: int) -> list[int]:
    zero_edge_path = _search_zero_edge_path_rec(network, flow, source, sink, set())
    if zero_edge_path is not None:
        zero_edge_path.reverse()
    return zero_edge_path


def _search_zero_edge_path_rec(network: DiGraph, flow: DiGraph, source: int, sink: int, visited: set[int]) -> list[int]:
    visited.add(source)
    for neighbor in flow.neighbors_out(source):
        if network.edge_label(source, neighbor) > flow.edge_label(source, neighbor):
            return [neighbor, source]
        if neighbor not in visited:
            path = _search_zero_edge_path_rec(network, flow, neighbor, sink, visited)
            if path is not None:
                path.append(source)
                return path
    return None


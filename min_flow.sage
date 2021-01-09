def min_flow(flow_network, source, sink):
    """Edge labels are the flow lower bounds"""
    [cardinal, feasible_flow_graph] = _feasible_flow(flow_network, source, sink)
    # breakpoint()
    return _reduce_to_min_flow(flow_network, cardinal, feasible_flow_graph, source, sink)


def _feasible_flow(flow_network, source, sink):
    # We have to do a max flow in the converted flow network.
    # To convert it, we sum the lower bounds of the edges and set that as the capacity
    # of each edge. Then, we subtract the lower bound from each edge capacity,
    # and add demands to the vertices according to the lower bounds.
    # With the demands, we can convert it to a simple max flow network by adding
    # a source and a sink with appropiate edge capacities.
    capacity = _edge_labels_sum(flow_network)
    converted = flow_network.copy()
    _clear_vertex_demands(converted)
    _set_capacities_and_demands(converted, capacity, source, sink)
    new_source = converted.add_vertex()
    new_sink = converted.add_vertex()
    _convert_to_flow_without_demands(converted, source, sink, new_source, new_sink, capacity)
    [cardinal, result] = converted.flow(
        new_source, new_sink, value_only=False, integer=True, use_edge_labels=True
    )
    if result.has_vertex(new_source):
        result.delete_vertex(new_source)
    if result.has_vertex(new_sink):
        result.delete_vertex(new_sink)
    if not result.has_edge(sink, source):
        cardinal = 0
    else:
        cardinal = result.edge_label(sink, source)
        result.delete_edge(sink, source)

    _fill_missing_edges(result, flow_network)
    _add_labels(result, flow_network)

    return [cardinal, result]


def _reduce_to_min_flow(flow_network, feasible_flow_cardinal, feasible_flow, source, sink):
    # Now, we have to convert the flow network to another max flow network,
    # and then subtract the result of that max flow network from the feasible one
    # to get the min flow network.
    max_flow_network = _subtract_edge_labels(feasible_flow, flow_network)
    [max_flow_cardinal, max_flow_result] = max_flow_network.flow(
        source, sink, value_only=False, integer=True, use_edge_labels=True
    )
    _fill_missing_edges(max_flow_result, flow_network)
    return [
        feasible_flow_cardinal - max_flow_cardinal,
        _subtract_edge_labels(feasible_flow, max_flow_result)
    ]


def _subtract_edge_labels(original_network, subtracted_network):
    result = subtracted_network.copy()
    for edge in subtracted_network.edge_iterator():
        (vertex_from, vertex_to, lower_bound) = edge
        feasible_edge_flow = original_network.edge_label(vertex_from, vertex_to)
        result.set_edge_label(vertex_from, vertex_to, feasible_edge_flow - lower_bound)
    return result

def _edge_labels_sum(flow_network):
    return sum(edge[2] for edge in flow_network.edge_iterator())


def _clear_vertex_demands(flow_network):
    for vertex in flow_network:
        flow_network.set_vertex(vertex, 0)


def _set_capacities_and_demands(converted_network, capacity, source, sink):
    for edge in converted_network.edge_iterator():
        (vertex_from, vertex_to, lower_bound) = edge
        converted_network.set_edge_label(vertex_from , vertex_to, capacity - lower_bound)
        from_demand = converted_network.get_vertex(vertex_from) + lower_bound
        converted_network.set_vertex(vertex_from, from_demand)
        to_demand = converted_network.get_vertex(vertex_to) - lower_bound
        converted_network.set_vertex(vertex_to, to_demand)


def _convert_to_flow_without_demands(
    network_with_demands, source, sink, new_source, new_sink, flow_upper_bound):
    network_with_demands.add_edge(sink, source, flow_upper_bound)
    for vertex in network_with_demands:
        demand = network_with_demands.get_vertex(vertex)
        if demand:
            if demand < 0:
                network_with_demands.add_edge(new_source, vertex, -demand)
            else:
                network_with_demands.add_edge(vertex, new_sink, demand)


def _fill_missing_edges(flow_result, original_graph):
    for edge in original_graph.edge_iterator():
        vertex_from = edge[0]
        vertex_to = edge[1]
        if not flow_result.has_vertex(vertex_from):
            flow_result.add_vertex(vertex_from)
        if not flow_result.has_vertex(vertex_to):
            flow_result.add_vertex(vertex_to)
        if not flow_result.has_edge(vertex_from, vertex_to):
            flow_result.add_edge(vertex_from, vertex_to, 0)

def _add_labels(graph, added):
    for edge in graph.edge_iterator():
        (vertex_from, vertex_to, label) = edge
        label += added.edge_label(vertex_from, vertex_to)
        graph.set_edge_label(vertex_from, vertex_to, label)
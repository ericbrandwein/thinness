load("min_flow.sage")

_SOURCE_VERTEX = -1
_SINK_VERTEX = -2

def cocomparability_coloring(graph):
    return comparability_clique_covering(graph.complement())


def comparability_clique_covering(graph):
    transitive_orientation = comparability_transitive_orientation(graph)
    flow_network = _transform_to_min_flow_network(transitive_orientation)
    [min_flow_cardinal, solved_flow_graph] = min_flow(
        flow_network, _SOURCE_VERTEX, _SINK_VERTEX)
    return [0 for i in range(int(round(min_flow_cardinal)))]


def comparability_transitive_orientation(graph):
    return graph.is_comparability(certificate=True)[1]


def _transform_to_min_flow_network(transitive_orientation):
    result = transitive_orientation.copy()
    assign_heights(result)
    _add_source(result)
    _add_sink(result)
    return _split_nodes(result)


def assign_heights(graph):
    """
    Assign an integer to each vertex which is equal to the maximum between the heights of its
    out-neighbors plus 1.

    If the vertex has no out-neighbors, its height is 1.
    """

    for vertex in graph:
        assign_height(graph, vertex)


def assign_height(graph, vertex):
    height = graph.get_vertex(vertex)
    if not height:
        height = 0
        for neighbor in graph.neighbor_out_iterator(vertex):
            height = max(height, assign_height(graph, neighbor))
        height += 1
        graph.set_vertex(vertex, height)

    return height


def _add_source(transitive_orientation):
    vertices_with_no_in_neighbors = list(filter(
        lambda vertex: len(transitive_orientation.neighbors_in(vertex)) == 0,
        transitive_orientation
    ))
    transitive_orientation.add_vertex(_SOURCE_VERTEX)

    for vertex in vertices_with_no_in_neighbors:
        transitive_orientation.add_edge(_SOURCE_VERTEX, vertex)


def _add_sink(transitive_orientation):
    transitive_orientation.add_vertex(_SINK_VERTEX)
    vertices_with_height_one = filter(
        lambda vertex: transitive_orientation.get_vertex(vertex) == 1,
        transitive_orientation
    )

    for vertex in vertices_with_height_one:
        transitive_orientation.add_edge(vertex, _SINK_VERTEX)


def _split_nodes(digraph):
    # The labels are the lower bounds for the flow network
    result = graphs.EmptyGraph().to_directed()
    result.add_vertices([_SINK_VERTEX, _SOURCE_VERTEX])
    for vertex in digraph:
        if vertex != _SOURCE_VERTEX and vertex != _SINK_VERTEX:
            source = (vertex, _SOURCE_VERTEX)
            sink = (vertex, _SINK_VERTEX)
            result.add_vertices([source, sink])
            result.add_edge(source, sink, 1)

    for vertex in digraph:
        if vertex == _SOURCE_VERTEX:
            vertex_from = vertex
        else:
            vertex_from = (vertex, _SINK_VERTEX)
        for neighbor in digraph.neighbor_out_iterator(vertex):
            if neighbor == _SINK_VERTEX:
                vertex_to = neighbor
            else:
                vertex_to = (neighbor, _SOURCE_VERTEX)
            result.add_edge(vertex_from, vertex_to, 0)

    return result


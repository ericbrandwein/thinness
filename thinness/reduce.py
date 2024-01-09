import itertools

from sage.graphs.graph import Graph 


def reduce_graph(graph: Graph) -> Graph:
    """Reduce the graph to a smaller graph with the same thinness."""
    reduced_graph = _remove_same_closed_neighborhood_vertices(graph)
    reduced_graph = _remove_same_open_neighborhood_vertices(reduced_graph)
    reduced_graph, reduced_thinness = _remove_non_adjacent_pairs_of_universal_vertices(reduced_graph)
    return reduced_graph, reduced_thinness


def _remove_same_closed_neighborhood_vertices(graph: Graph) -> Graph:
    common_neighbors = graph.common_neighbors_matrix(nonedgesonly=False)
    reduced_graph = graph.copy()
    for u, v in graph.edge_iterator(labels=False):
        if u in reduced_graph and v in reduced_graph and graph.degree(u) == graph.degree(v) == common_neighbors[u, v] + 1:
            reduced_graph.delete_vertex(u)
    reduced_graph.relabel()
    return reduced_graph


def _remove_same_open_neighborhood_vertices(graph: Graph) -> Graph:
    common_neighbors = graph.common_neighbors_matrix(nonedgesonly=False)
    reduced_graph = graph.copy()
    non_edges = ((u, v) for u, v in itertools.combinations(graph.vertices(), 2) if not graph.has_edge(u, v))
    pairs_with_same_open_neighborhoods = ((u, v) for u, v in non_edges if graph.degree(u) == graph.degree(v) == common_neighbors[u, v])
    for u, v in pairs_with_same_open_neighborhoods:
        if u in reduced_graph and v in reduced_graph:
            for w in graph.vertex_iterator():
                if u != w and v != w and w in reduced_graph and not graph.has_edge(u, w) and not graph.has_edge(v, w) and graph.degree(w) == graph.degree(u) == common_neighbors[u, w]:
                    reduced_graph.delete_vertex(w)
    reduced_graph.relabel()
    return reduced_graph


def _remove_non_adjacent_pairs_of_universal_vertices(graph: Graph) -> tuple[Graph, int]:
    reduced_graph = graph.copy()
    reduced_thinness = 0
    for u, v in itertools.combinations(graph.vertices(), 2):
        if reduced_graph.order() == 2:
            break
        if graph.degree(u) == graph.degree(v) == graph.order() - 2 and not graph.has_edge(u, v):
            reduced_graph.delete_vertex(u)
            reduced_graph.delete_vertex(v)
            if not _is_complete(reduced_graph):
                reduced_thinness += 1
    reduced_graph.relabel()
    return reduced_graph, reduced_thinness


def _is_complete(graph: Graph) -> bool:
    return graph.order() * (graph.order() - 1) // 2 == graph.size()
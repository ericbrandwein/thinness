import itertools

from sage.graphs.graph import Graph 


def reduce_graph(graph: Graph) -> Graph:
    """Reduce the graph to a smaller graph with the same thinness."""
    common_neighbors = graph.common_neighbors_matrix(nonedgesonly=False)
    reduced_graph = _remove_same_closed_neighborhood_vertices(graph, common_neighbors)
    reduced_graph = _remove_same_open_neighborhood_vertices(reduced_graph, common_neighbors)
    reduced_graph.relabel()
    return reduced_graph


def _remove_same_closed_neighborhood_vertices(graph: Graph, common_neighbors) -> Graph:
    reduced_graph = graph.copy()
    for u, v in graph.edge_iterator(labels=False):
        if u in reduced_graph and v in reduced_graph and graph.degree(u) == graph.degree(v) == common_neighbors[u, v] + 1:
            reduced_graph.delete_vertex(u)
    return reduced_graph


def _remove_same_open_neighborhood_vertices(graph: Graph, common_neighbors) -> Graph:
    reduced_graph = graph.copy()
    non_edges = ((u, v) for u, v in itertools.combinations(graph.vertices(), 2) if not graph.has_edge(u, v))
    pairs_with_same_open_neighborhoods = ((u, v) for u, v in non_edges if graph.degree(u) == graph.degree(v) == common_neighbors[u, v])
    for u, v in pairs_with_same_open_neighborhoods:
        if u in reduced_graph and v in reduced_graph:
            for w in graph.vertex_iterator():
                if u != w and v != w and w in reduced_graph and not graph.has_edge(u, w) and not graph.has_edge(v, w) and graph.degree(w) == graph.degree(u) == common_neighbors[u, w]:
                    reduced_graph.delete_vertex(w)
    return reduced_graph
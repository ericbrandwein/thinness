from sage.graphs.graph import Graph


def calculate_thinness_with_dynamic_programming(graph: Graph, upper_bound=None):
    """upper_bound is exclusive"""
    if upper_bound is None:
        upper_bound = graph.order()
    upper_bound_by_pathwidth = max(graph.pathwidth(certificate=False), 1)
    upper_bound = min(upper_bound_by_pathwidth, upper_bound)

    valid_prefixes = {(-1,) * graph.order()}
    prefixes_length = 0
    new_valid_prefixes = set()
    while prefixes_length < graph.order() and len(valid_prefixes) > 0:
        prefixes_length += 1
        for prefix in valid_prefixes:
            part_suffix_neighbors = _get_part_suffix_neighbors(graph, prefix)
            for vertex in range(graph.order()):
                if prefix[vertex] == -1:
                    vertex_suffix_neighbors = _get_vertex_suffix_neighbors(graph, prefix, vertex)
                    for part in range(upper_bound - 1):
                        neighbors = part_suffix_neighbors.get(part, set())
                        if neighbors.issubset(vertex_suffix_neighbors):
                            new_prefix = list(prefix)
                            new_prefix[vertex] = part
                            new_valid_prefixes.add(tuple(new_prefix))
        valid_prefixes = new_valid_prefixes
        new_valid_prefixes = set()

    if len(valid_prefixes) == 0:
        return upper_bound
    else:
        return min(
            max(prefix) + 1
            for prefix in valid_prefixes
        )


def _get_part_suffix_neighbors(graph: Graph, prefix: tuple) -> dict:
    part_neighbors = {}
    for vertex in range(graph.order()):
        part = prefix[vertex]
        if part != -1:
            part_neighbors.setdefault(part, set()).update(graph.neighbors(vertex))
    suffix_vertices = _get_suffix_vertices(graph, prefix)
    for neighbors in part_neighbors.values():
        neighbors.intersection_update(suffix_vertices)
    return part_neighbors


def _get_vertex_suffix_neighbors(graph: Graph, prefix: tuple, vertex: int) -> set:
    suffix_vertices = _get_suffix_vertices(graph, prefix)
    neighbors = set(graph.neighbors(vertex, closed=True))
    return neighbors.intersection(suffix_vertices)


def _get_suffix_vertices(graph: Graph, prefix: tuple) -> set:
    return {
        vertex
        for vertex in range(graph.order())
        if prefix[vertex] == -1
    }
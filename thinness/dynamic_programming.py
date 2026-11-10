from sage.graphs.graph import Graph


def calculate_thinness_with_dynamic_programming(graph: Graph, upper_bound=None, count_states=False):
    """Builds the order vertex by vertex, adding each vertex to a part or to a new one.

    A state is the set of placed vertices and the suffix neighbors of each part, that is,
    the vertices not placed yet that are adjacent to some vertex of the part. If the
    solution is consistent, these are the suffix neighbors of the last vertex of the part,
    so there are at most 3^n states, and at most 2^n * n^k with k parts. Parts without
    suffix neighbors accept any vertex, so only their number is kept, and of the states
    that only differ in that number, only the one with the fewest is kept.

    upper_bound is exclusive. With count_states, also returns the number of states explored.
    """
    upper_bound = _upper_bound(graph, upper_bound)
    max_parts = upper_bound - 1
    vertices = list(graph)
    index = {vertex: i for i, vertex in enumerate(vertices)}
    neighbors = [
        sum(1 << index[neighbor] for neighbor in graph.neighbor_iterator(vertex))
        for vertex in vertices
    ]
    all_vertices = (1 << len(vertices)) - 1

    # (placed vertices, sorted suffix neighbors of the parts that have some) -> fewest parts without them.
    current_states = {(0, ()): 0}
    states = 1
    for _ in vertices:
        next_states = {}

        def add_state(placed, parts_suffix_neighbors, parts_without_suffix_neighbors):
            parts_without_suffix_neighbors += parts_suffix_neighbors.count(0)
            parts_with_suffix_neighbors = tuple(sorted(part for part in parts_suffix_neighbors if part))
            if len(parts_with_suffix_neighbors) + parts_without_suffix_neighbors > max_parts:
                return
            key = (placed, parts_with_suffix_neighbors)
            if parts_without_suffix_neighbors < next_states.get(key, max_parts + 1):
                next_states[key] = parts_without_suffix_neighbors

        for (placed, parts_with_suffix_neighbors), parts_without_suffix_neighbors in current_states.items():
            for vertex in range(len(vertices)):
                bit = 1 << vertex
                if placed & bit:
                    continue
                suffix = all_vertices & ~placed & ~bit
                vertex_suffix_neighbors = neighbors[vertex] & suffix
                remaining = [part & suffix for part in parts_with_suffix_neighbors]

                # Joining a part without suffix neighbors is always possible, and leaves one part
                # less than starting a new one.
                if parts_without_suffix_neighbors > 0:
                    add_state(placed | bit, remaining + [vertex_suffix_neighbors], parts_without_suffix_neighbors - 1)
                else:
                    add_state(placed | bit, remaining + [vertex_suffix_neighbors], 0)

                tried = set()
                for i, part in enumerate(remaining):
                    if part in tried or part & ~vertex_suffix_neighbors:
                        continue
                    tried.add(part)
                    add_state(
                        placed | bit,
                        remaining[:i] + remaining[i + 1:] + [vertex_suffix_neighbors],
                        parts_without_suffix_neighbors,
                    )

        current_states = next_states
        states += len(current_states)
        if not current_states:
            break

    # When every vertex is placed, no part has suffix neighbors.
    thinness = min(current_states.values(), default=upper_bound)
    return (thinness, states) if count_states else thinness


def _upper_bound(graph: Graph, upper_bound) -> int:
    if upper_bound is None:
        upper_bound = graph.order()
    upper_bound_by_pathwidth = max(graph.pathwidth(certificate=False), 1)
    return min(upper_bound_by_pathwidth, upper_bound)

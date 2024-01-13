from sage.graphs.graph import Graph
from sage.data_structures.bitset import Bitset
from sage.data_structures.binary_matrix cimport *
from sage.graphs.base.static_dense_graph cimport dense_graph_init
from cysignals.memory cimport check_malloc, sig_malloc, sig_free
from cysignals.signals cimport sig_on, sig_off 

DEFAULT_MAX_PREFIX_LENGTH = 15
DEFAULT_MAX_SEEN_ENTRIES = 1_000_000


def calculate_thinness_with_branch_and_bound(
    graph: Graph, 
    lower_bound: int = 1, 
    upper_bound: int = None, 
    max_prefix_length: int = DEFAULT_MAX_PREFIX_LENGTH, 
    max_seen_entries: int = DEFAULT_MAX_SEEN_ENTRIES
) -> int:
    components = [graph.subgraph(component, immutable=False) for component in graph.connected_components()]
    for component in components:
        component.relabel()
    return max(
        calculate_thinness_of_connected_graph(
            component, 
            lower_bound, 
            upper_bound, 
            max_prefix_length, 
            max_seen_entries
        ) for component in components)


def calculate_thinness_of_connected_graph(
    graph: Graph, 
    lower_bound: int = 1, 
    upper_bound: int = None, 
    max_prefix_length: int = DEFAULT_MAX_PREFIX_LENGTH, 
    max_seen_entries: int = DEFAULT_MAX_SEEN_ENTRIES
) -> int:
    """upper_bound is exclusive."""
    if upper_bound is None:
        upper_bound = max(graph.pathwidth(), 1)
    if upper_bound == 1:
        return 1

    cdef int max_branch_and_bound_thinness = upper_bound - 1

    cdef binary_matrix_t adjacency_matrix
    dense_graph_init(adjacency_matrix, graph)

    cdef bitset_t prefix_vertices
    bitset_init(prefix_vertices, adjacency_matrix.n_cols)

    cdef bitset_t suffix_vertices
    bitset_init(suffix_vertices, adjacency_matrix.n_cols)
    bitset_complement(suffix_vertices, suffix_vertices)

    cdef binary_matrix_t new_prefixes
    binary_matrix_init(new_prefixes, adjacency_matrix.n_cols, adjacency_matrix.n_cols)

    cdef binary_matrix_t new_suffixes
    binary_matrix_init(new_suffixes, adjacency_matrix.n_cols, adjacency_matrix.n_cols)
    
    cdef int* part_of = <int*>sig_malloc(sizeof(int) * adjacency_matrix.n_cols)
    cdef int* parts_rename = <int*>sig_malloc(sizeof(int) * max_branch_and_bound_thinness)

    cdef binary_matrix_t part_neighbors
    binary_matrix_init(part_neighbors, max_branch_and_bound_thinness, adjacency_matrix.n_cols)

    cdef binary_matrix_t previous_part_neighbors
    binary_matrix_init(previous_part_neighbors, adjacency_matrix.n_cols, adjacency_matrix.n_cols)

    cdef binary_matrix_t parts_for_vertices
    binary_matrix_init(parts_for_vertices, adjacency_matrix.n_cols, max_branch_and_bound_thinness)
    
    cdef bitset_t suffix_neighbors_of_vertex
    bitset_init(suffix_neighbors_of_vertex, adjacency_matrix.n_cols)

    cdef bitset_t suffix_neighbors_of_part
    bitset_init(suffix_neighbors_of_part, adjacency_matrix.n_cols)    
    
    cdef dict seen_states = dict() 

    cdef int seen_entries = 0

    sig_on()
    branch_and_bound_thinness = _branch_and_bound(
        graph=adjacency_matrix,
        part_of=part_of,
        parts_rename=parts_rename,
        parts_used=0,
        prefix_vertices=prefix_vertices,
        suffix_vertices=suffix_vertices,
        new_prefixes=new_prefixes,
        new_suffixes=new_suffixes,
        part_neighbors=part_neighbors,
        previous_part_neighbors=previous_part_neighbors,
        parts_for_vertices=parts_for_vertices,
        suffix_neighbors_of_vertex=suffix_neighbors_of_vertex,
        suffix_neighbors_of_part=suffix_neighbors_of_part,
        seen_states=seen_states,
        seen_entries=&seen_entries,
        max_prefix_length=max_prefix_length,
        max_seen_entries=max_seen_entries,
        lower_bound=lower_bound,
        upper_bound=max_branch_and_bound_thinness
    )
    sig_off()

    binary_matrix_free(adjacency_matrix)
    bitset_free(prefix_vertices)
    bitset_free(suffix_vertices)
    binary_matrix_free(new_prefixes)
    binary_matrix_free(new_suffixes)
    sig_free(part_of)
    sig_free(parts_rename)
    binary_matrix_free(part_neighbors)
    binary_matrix_free(previous_part_neighbors)
    binary_matrix_free(parts_for_vertices)
    bitset_free(suffix_neighbors_of_vertex)
    bitset_free(suffix_neighbors_of_part)

    return branch_and_bound_thinness if branch_and_bound_thinness != -1 else upper_bound


cdef int _branch_and_bound(
    binary_matrix_t graph,
    int* part_of,
    int* parts_rename,
    int parts_used,
    bitset_t prefix_vertices,
    bitset_t suffix_vertices,
    binary_matrix_t new_prefixes,
    binary_matrix_t new_suffixes,
    binary_matrix_t part_neighbors,
    binary_matrix_t previous_part_neighbors,
    binary_matrix_t parts_for_vertices,
    bitset_t suffix_neighbors_of_vertex,
    bitset_t suffix_neighbors_of_part,
    dict seen_states,
    int* seen_entries,
    int max_prefix_length,
    int max_seen_entries,
    int lower_bound,
    int upper_bound
):
    cdef int level = bitset_len(prefix_vertices)
    cdef bitset_t new_prefix = new_prefixes.rows[level]
    bitset_copy(new_prefix, prefix_vertices)

    cdef bitset_t new_suffix = new_suffixes.rows[level]
    bitset_copy(new_suffix, suffix_vertices)

    _increment_prefix_greedily(
        graph,
        new_prefix,
        new_suffix,
        parts_used,
        part_of,
        part_neighbors,
        suffix_neighbors_of_vertex,
        suffix_neighbors_of_part
    )

    if bitset_isempty(new_suffix) and parts_used <= upper_bound:
        return parts_used

    if _check_state_seen(
        seen_states,
        seen_entries,
        new_prefix,
        new_suffix,
        parts_used,
        part_neighbors,
        suffix_neighbors_of_part,
        max_prefix_length,
        max_seen_entries
    ):
        return -1
    
    cdef int best_solution_found = -1
    cdef int vertex = bitset_next(new_suffix, 0)
    cdef bitset_s* parts_for_vertex
    cdef int part
    while vertex != -1:
        _move(new_suffix, new_prefix, vertex)

        parts_for_vertex = _get_available_parts_for_vertex(
            vertex, 
            parts_used,
            parts_for_vertices,
            part_neighbors,
            new_suffix,
            graph.rows[vertex],
            suffix_neighbors_of_vertex,
            suffix_neighbors_of_part
        )

        part = bitset_next(parts_for_vertex, 0)

        while part != -1:
            part_of[vertex] = part

            _update_part_neighbors(
                part_neighbors.rows[part],
                previous_part_neighbors.rows[vertex],
                graph.rows[vertex]
            )
            
            current_solution = _branch_and_bound(
                graph,
                part_of,
                parts_rename,
                parts_used,
                new_prefix,
                new_suffix,
                new_prefixes,
                new_suffixes,
                part_neighbors,
                previous_part_neighbors,
                parts_for_vertices,
                suffix_neighbors_of_vertex,
                suffix_neighbors_of_part,
                seen_states,
                seen_entries,
                max_prefix_length,
                max_seen_entries,
                lower_bound,
                upper_bound
            )

            _undo_update_part_neighbors(
                part_neighbors.rows[part],
                previous_part_neighbors.rows[vertex]
            )

            if current_solution != -1:
                best_solution_found = current_solution
                upper_bound = best_solution_found - 1
                if upper_bound < lower_bound:
                    return best_solution_found

            part = bitset_next(parts_for_vertex, part + 1)

        _move(new_prefix, new_suffix, vertex)
        vertex = bitset_next(new_suffix, vertex + 1)

    if parts_used < upper_bound:
        part = parts_used
        current_parts_used = parts_used + 1
        vertex = bitset_next(new_suffix, 0)
        while vertex != -1:
            _move(new_suffix, new_prefix, vertex)
            part_of[vertex] = part

            _update_part_neighbors(
                part_neighbors.rows[part],
                previous_part_neighbors.rows[vertex],
                graph.rows[vertex]
            )

            current_solution = _branch_and_bound(
                graph,
                part_of,
                parts_rename,
                current_parts_used,
                new_prefix,
                new_suffix,
                new_prefixes,
                new_suffixes,
                part_neighbors,
                previous_part_neighbors,
                parts_for_vertices,
                suffix_neighbors_of_vertex,
                suffix_neighbors_of_part,
                seen_states,
                seen_entries,
                max_prefix_length,
                max_seen_entries,
                max(lower_bound, current_parts_used),
                upper_bound
            )

            _undo_update_part_neighbors(
                part_neighbors.rows[part],
                previous_part_neighbors.rows[vertex]
            )

            if current_solution != -1:
                best_solution_found = current_solution
                upper_bound = best_solution_found - 1
                if upper_bound < lower_bound:
                    return best_solution_found
            
            _move(new_prefix, new_suffix, vertex)
            vertex = bitset_next(new_suffix, vertex + 1)

    return best_solution_found


cdef inline void _increment_prefix_greedily(
    binary_matrix_t graph,
    bitset_t prefix_vertices,
    bitset_t suffix_vertices,
    int parts_used,
    int* part_of,
    binary_matrix_t part_neighbors,
    bitset_t suffix_neighbors_of_vertex,
    bitset_t suffix_neighbors_of_part,
):
    """Add to prefix all vertices that have the same suffix neighbors as one of the parts."""
    cdef int vertex
    cdef int part
    cdef bint prefix_changed = True
    while prefix_changed:
        prefix_changed = False
        vertex = bitset_next(suffix_vertices, 0)
        while vertex != -1:
            _move(suffix_vertices, prefix_vertices, vertex)

            part = _find_greedy_part_for_vertex(
                vertex,
                graph,
                suffix_vertices,
                parts_used,
                part_neighbors,
                suffix_neighbors_of_vertex,
                suffix_neighbors_of_part,
            )

            if part != -1:
                part_of[vertex] = part
                prefix_changed = True
                break
            else:
                _move(prefix_vertices, suffix_vertices, vertex)
                vertex = bitset_next(suffix_vertices, vertex + 1)


cdef inline int _find_greedy_part_for_vertex(
    int vertex,
    binary_matrix_t graph,
    bitset_t suffix_vertices,
    int parts_used,
    binary_matrix_t part_neighbors,
    bitset_t suffix_neighbors_of_vertex,
    bitset_t suffix_neighbors_of_part,
):
    bitset_intersection(
        suffix_neighbors_of_vertex, 
        graph.rows[vertex], 
        suffix_vertices
    )
    for part in range(parts_used):
        if _is_greedy_part_for_vertex(
            part,
            suffix_vertices,
            part_neighbors,
            suffix_neighbors_of_vertex,
            suffix_neighbors_of_part,
        ):
            return part
    return -1


cdef inline bint _is_greedy_part_for_vertex(
    int part,
    bitset_t suffix_vertices,
    binary_matrix_t part_neighbors,
    bitset_t suffix_neighbors_of_vertex,
    bitset_t suffix_neighbors_of_part,
):
    bitset_intersection(
        suffix_neighbors_of_part,
        part_neighbors.rows[part],
        suffix_vertices
    )
    return bitset_eq(suffix_neighbors_of_part, suffix_neighbors_of_vertex)


cdef inline bint _check_state_seen(
    dict seen_states,
    int* seen_entries,
    bitset_t prefix_vertices,
    bitset_t suffix_vertices,
    int parts_used,
    binary_matrix_t part_neighbors,
    bitset_t suffix_neighbors_of_part,
    int max_prefix_length,
    int max_seen_entries
):
    if bitset_len(prefix_vertices) > max_prefix_length:
        return False

    cdef frozenset frozen_prefix_vertices = frozenset(bitset_list(prefix_vertices))
    cdef frozenset frozen_part_neighbors = _build_frozen_part_neighbors(
        suffix_vertices, parts_used, part_neighbors, suffix_neighbors_of_part)
    cdef dict seen_part_neighbors
    cdef int parts_used_before
    cdef bint state_seen = False
    if frozen_prefix_vertices in seen_states:
        seen_part_neighbors = seen_states[frozen_prefix_vertices]
        if frozen_part_neighbors in seen_part_neighbors:
            parts_used_before = seen_part_neighbors[frozen_part_neighbors]
            if parts_used_before <= parts_used:
                state_seen = True
            else:
                seen_part_neighbors[frozen_part_neighbors] = parts_used
        elif seen_entries[0] < max_seen_entries:
            seen_part_neighbors[frozen_part_neighbors] = parts_used
            seen_entries[0] += 1
    elif seen_entries[0] < max_seen_entries:
        seen_states[frozen_prefix_vertices] = {frozen_part_neighbors: parts_used}
        seen_entries[0] += 1
    
    return state_seen


cdef inline _build_frozen_part_neighbors(
    bitset_t suffix_vertices,
    int parts_used, 
    binary_matrix_t part_neighbors,
    bitset_t suffix_neighbors_of_part
):
    cdef set suffix_part_neighbors = set()
    cdef frozenset suffix_neighbors_of_part_set 
    for part in range(parts_used):
        bitset_intersection(
            suffix_neighbors_of_part, part_neighbors.rows[part], suffix_vertices)
        suffix_neighbors_of_part_set = frozenset(bitset_list(suffix_neighbors_of_part))
        suffix_part_neighbors.add(suffix_neighbors_of_part_set)
    return frozenset(suffix_part_neighbors)
        

cdef inline void _move(bitset_t bitset_from, bitset_t bitset_to, int vertex):
    bitset_remove(bitset_from, vertex)
    bitset_add(bitset_to, vertex)


cdef inline void _update_part_neighbors(
    bitset_t neighbors_of_part,
    bitset_t previous_neighbors_of_part,
    bitset_t neighbors_of_vertex
):
    bitset_copy(previous_neighbors_of_part, neighbors_of_part)
    bitset_union(neighbors_of_part, neighbors_of_part, neighbors_of_vertex)


cdef inline void _undo_update_part_neighbors(
    bitset_t neighbors_of_part,
    bitset_t previous_neighbors_of_part
):
    bitset_copy(neighbors_of_part, previous_neighbors_of_part)


cdef inline bitset_s* _get_available_parts_for_vertex(
    int vertex, 
    int parts_used,
    binary_matrix_t parts_for_vertices,
    binary_matrix_t part_neighbors,
    bitset_t suffix_vertices,
    bitset_t neighbors_of_vertex,
    bitset_t suffix_neighbors_of_vertex,
    bitset_t suffix_neighbors_of_part
):
    bitset_intersection(suffix_neighbors_of_vertex, neighbors_of_vertex, suffix_vertices)

    cdef bitset_s* parts_for_vertex = parts_for_vertices.rows[vertex]
    bitset_clear(parts_for_vertex)
    for part in range(parts_used):
        if _is_available_part_for_vertex(
            part_neighbors.rows[part],
            suffix_vertices,
            suffix_neighbors_of_vertex,
            suffix_neighbors_of_part
        ):
            bitset_add(parts_for_vertex, part)
    return parts_for_vertex


cdef inline bint _is_available_part_for_vertex(
    bitset_t neighbors_of_part,
    bitset_t suffix_vertices,
    bitset_t suffix_neighbors_of_vertex,
    bitset_t suffix_neighbors_of_part,
):
    bitset_intersection(
        suffix_neighbors_of_part,
        neighbors_of_part,
        suffix_vertices
    )
    return bitset_issubset(suffix_neighbors_of_part, suffix_neighbors_of_vertex)

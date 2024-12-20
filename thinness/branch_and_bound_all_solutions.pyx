import itertools

from sage.graphs.graph import Graph
from sage.data_structures.bitset import Bitset
from sage.data_structures.binary_matrix cimport *
from sage.graphs.base.static_dense_graph cimport dense_graph_init
from cysignals.memory cimport check_malloc, sig_malloc, sig_free
from cysignals.signals cimport sig_on, sig_off 
from sage.graphs.graph_decompositions.vertex_separation import vertex_separation

from thinness.consistent_solution import ConsistentSolution 
from thinness.vertex_separation import solution_from_vertex_separation

DEFAULT_MAX_PREFIX_LENGTH = 15
DEFAULT_MAX_SEEN_ENTRIES = 1_000_000


def calculate_thinness_of_connected_graph(
    graph: Graph, 
    lower_bound: int = 1, 
    upper_bound: int = None,
) -> list[ConsistentSolution]:
    """upper_bound is exclusive.
    graph must have vertices labeled as integers from 0 to n-1."""
    vertex_separation_value, vertex_separation_order = vertex_separation(graph)
    upper_bound_from_vertex_separation = max(vertex_separation_value, 1)
    upper_bound = (
        upper_bound_from_vertex_separation
        if upper_bound is None
        else min(upper_bound, upper_bound_from_vertex_separation)
    )

    cdef int max_branch_and_bound_thinness = upper_bound

    cdef binary_matrix_t adjacency_matrix
    dense_graph_init(adjacency_matrix, graph)

    cdef int n = adjacency_matrix.n_cols

    cdef bitset_t prefix_vertices
    bitset_init(prefix_vertices, n)

    cdef bitset_t suffix_vertices
    bitset_init(suffix_vertices, n)
    bitset_complement(suffix_vertices, suffix_vertices)

    cdef binary_matrix_t new_suffixes
    binary_matrix_init(new_suffixes, n+1, n)
    
    cdef int* prefix = <int*>sig_malloc(sizeof(int) * n)
    cdef int* part_of = <int*>sig_malloc(sizeof(int) * n)
    cdef int* parts_rename = <int*>sig_malloc(sizeof(int) * max_branch_and_bound_thinness)

    cdef binary_matrix_t part_neighbors
    binary_matrix_init(part_neighbors, max_branch_and_bound_thinness, n)

    cdef binary_matrix_t previous_part_neighbors
    binary_matrix_init(previous_part_neighbors, n, n)

    cdef binary_matrix_t parts_for_vertices
    binary_matrix_init(parts_for_vertices, n, max_branch_and_bound_thinness)
    
    cdef bitset_t suffix_neighbors_of_vertex
    bitset_init(suffix_neighbors_of_vertex, n)

    cdef binary_matrix_t part_suffix_neighbors
    binary_matrix_init(part_suffix_neighbors, max_branch_and_bound_thinness, n)
    
    cdef bitset_t vertices_not_added
    bitset_init(vertices_not_added, n)
    
    cdef int* best_order = <int*>sig_malloc(sizeof(int) * n)
    cdef int* best_partition = <int*>sig_malloc(sizeof(int) * n)

    cdef bitset_t canonical_vertices
    bitset_init(canonical_vertices, n)
    _build_canonical_vertices(graph, canonical_vertices)

    cdef list solutions = []

    try:
        sig_on()
        branch_and_bound_thinness = _branch_and_bound(
            graph=adjacency_matrix,
            prefix=prefix,
            part_of=part_of,
            parts_rename=parts_rename,
            parts_used=0,
            prefix_vertices=prefix_vertices,
            suffix_vertices=suffix_vertices,
            new_suffixes=new_suffixes,
            part_neighbors=part_neighbors,
            previous_part_neighbors=previous_part_neighbors,
            parts_for_vertices=parts_for_vertices,
            suffix_neighbors_of_vertex=suffix_neighbors_of_vertex,
            part_suffix_neighbors=part_suffix_neighbors,
            vertices_not_added=vertices_not_added,
            canonical_vertices=canonical_vertices,
            lower_bound=lower_bound,
            upper_bound=max_branch_and_bound_thinness,
            best_order=best_order,
            best_partition=best_partition,
            solutions=solutions,
        )
        sig_off()
    finally:
        binary_matrix_free(adjacency_matrix)
        bitset_free(prefix_vertices)
        bitset_free(suffix_vertices)
        binary_matrix_free(new_suffixes)
        sig_free(prefix)
        sig_free(part_of)
        sig_free(parts_rename)
        binary_matrix_free(part_neighbors)
        binary_matrix_free(previous_part_neighbors)
        binary_matrix_free(parts_for_vertices)
        bitset_free(suffix_neighbors_of_vertex)
        binary_matrix_free(part_suffix_neighbors)
        bitset_free(canonical_vertices)
        sig_free(best_order)
        sig_free(best_partition)

    return [solution for solution in solutions if solution.thinness == branch_and_bound_thinness]


cdef _build_solution(int* best_order, int* best_partition, int thinness, int n):
    cdef list order = [best_order[i] for i in range(n)]
    cdef list partition = [set() for _ in range(thinness)]
    for vertex in range(n):
        partition[best_partition[vertex]].add(vertex)
    return ConsistentSolution(order, partition)


cdef inline void _build_canonical_vertices(graph: Graph, bitset_t canonical_vertices):
    cdef list orbit
    for orbit in graph.automorphism_group(orbits=True, return_group=False):
        bitset_add(canonical_vertices, <int> orbit[0])


cdef int _branch_and_bound(
    binary_matrix_t graph,
    int* prefix,
    int* part_of,
    int* parts_rename,
    int parts_used,
    bitset_t prefix_vertices,
    bitset_t suffix_vertices,
    binary_matrix_t new_suffixes,
    binary_matrix_t part_neighbors,
    binary_matrix_t previous_part_neighbors,
    binary_matrix_t parts_for_vertices,
    bitset_t suffix_neighbors_of_vertex,
    binary_matrix_t part_suffix_neighbors,
    bitset_t vertices_not_added,
    bitset_t canonical_vertices,
    int lower_bound,
    int upper_bound,
    int* best_order,
    int* best_partition,
    list solutions,
):
    cdef int level = _get_level(suffix_vertices)
  
    cdef bitset_t new_suffix = new_suffixes.rows[level]
    bitset_copy(new_suffix, suffix_vertices)

    _increment_prefix_greedily_on_existing_parts(
        graph,
        new_suffix,
        parts_used,
        prefix,
        part_of,
        part_neighbors,
        suffix_neighbors_of_vertex,
        part_suffix_neighbors
    )

    if bitset_isempty(new_suffix) and parts_used <= upper_bound:
        _copy_array(graph.n_cols, prefix, best_order)
        _copy_array(graph.n_cols, part_of, best_partition)
        solution = _build_solution(best_order, best_partition, parts_used, graph.n_cols)
        solutions.append(solution)
        return parts_used
    
    cdef int best_solution_found = _branch_adding_to_existing_part(
        graph,
        prefix,
        part_of,
        parts_rename,
        parts_used,
        prefix_vertices,
        new_suffix,
        new_suffixes,
        part_neighbors,
        previous_part_neighbors,
        parts_for_vertices,
        suffix_neighbors_of_vertex,
        part_suffix_neighbors,
        vertices_not_added,
        canonical_vertices,
        lower_bound,
        upper_bound,
        best_order,
        best_partition,
        solutions,
    )
    
    if best_solution_found != -1:
        upper_bound = best_solution_found
    
    cdef int new_part_solution
    cdef int part
    cdef int vertex_added_on_new_part
    if parts_used < upper_bound:
        parts_used += 1
        part = parts_used - 1
        lower_bound = max(lower_bound, parts_used)
        vertex_added_on_new_part = _add_vertex_to_prefix_greedily_on_part(
            part,
            graph,
            prefix_vertices,
            new_suffix,
            suffix_neighbors_of_vertex,
            part_suffix_neighbors,
            prefix,
            part_of,
            part_neighbors,
        )
        
        if vertex_added_on_new_part:
            new_part_solution = _branch_and_bound(
                graph,
                prefix,
                part_of,
                parts_rename,
                parts_used,
                prefix_vertices,
                new_suffix,
                new_suffixes,
                part_neighbors,
                previous_part_neighbors,
                parts_for_vertices,
                suffix_neighbors_of_vertex,
                part_suffix_neighbors,
                vertices_not_added,
                canonical_vertices,
                lower_bound,
                upper_bound,
                best_order,
                best_partition,
                solutions,
            )
        else:
            new_part_solution = _branch_adding_to_new_part(
                graph,
                prefix,
                part_of,
                parts_rename,
                parts_used,
                prefix_vertices,
                new_suffix,
                new_suffixes,
                part_neighbors,
                previous_part_neighbors,
                parts_for_vertices,
                suffix_neighbors_of_vertex,
                part_suffix_neighbors,
                vertices_not_added,
                canonical_vertices,
                lower_bound,
                upper_bound,
                best_order,
                best_partition,
                solutions,
            )

        if new_part_solution != -1:
            best_solution_found = new_part_solution

    return best_solution_found


cdef inline int _get_level(bitset_t suffix_vertices):
    return suffix_vertices.size - bitset_len(suffix_vertices)


cdef inline void _copy_array(int n, int* array_from, int* array_to):
    for i in range(n):
        array_to[i] = array_from[i]


cdef inline int _branch_adding_to_existing_part(
    binary_matrix_t graph,
    int* prefix,
    int* part_of,
    int* parts_rename,
    int parts_used,
    bitset_t prefix_vertices,
    bitset_t suffix_vertices,
    binary_matrix_t new_suffixes,
    binary_matrix_t part_neighbors,
    binary_matrix_t previous_part_neighbors,
    binary_matrix_t parts_for_vertices,
    bitset_t suffix_neighbors_of_vertex,
    binary_matrix_t part_suffix_neighbors,
    bitset_t vertices_not_added,
    bitset_t canonical_vertices,
    int lower_bound,
    int upper_bound,
    int* best_order,
    int* best_partition,
    list solutions,
):
    cdef int level = _get_level(suffix_vertices)
    cdef int best_solution_found = -1
    cdef bitset_t parts_for_vertex
    cdef int part
    bitset_clear(vertices_not_added)
    cdef int vertex = bitset_next(suffix_vertices, 0)
    while vertex != -1:
        bitset_discard(suffix_vertices, vertex)
        prefix[level] = vertex

        parts_for_vertex = _get_available_parts_for_vertex(
            vertex, 
            parts_used,
            parts_for_vertices,
            part_neighbors,
            suffix_vertices,
            graph.rows[vertex],
            suffix_neighbors_of_vertex,
            part_suffix_neighbors
        )

        if bitset_isempty(parts_for_vertex):
            bitset_add(vertices_not_added, vertex)
        part = bitset_next(parts_for_vertex, 0)
        while part != -1:
            current_solution = _branch_with_vertex_on_part(
                vertex,
                part,
                graph,
                prefix,
                part_of,
                parts_rename,
                parts_used,
                prefix_vertices,
                suffix_vertices,
                new_suffixes,
                part_neighbors,
                previous_part_neighbors,
                parts_for_vertices,
                suffix_neighbors_of_vertex,
                part_suffix_neighbors,
                vertices_not_added,
                canonical_vertices,
                lower_bound,
                upper_bound,
                best_order,
                best_partition,
                solutions,
            )

            if current_solution != -1:
                best_solution_found = current_solution
                upper_bound = best_solution_found
            part = bitset_next(parts_for_vertex, part + 1)

        bitset_add(suffix_vertices, vertex)
        vertex = bitset_next(suffix_vertices, vertex + 1)
    
    return best_solution_found


cdef inline bitset_s* _get_available_parts_for_vertex(
    int vertex, 
    int parts_used,
    binary_matrix_t parts_for_vertices,
    binary_matrix_t part_neighbors,
    bitset_t suffix_vertices,
    bitset_t neighbors_of_vertex,
    bitset_t suffix_neighbors_of_vertex,
    binary_matrix_t part_suffix_neighbors
):
    bitset_intersection(suffix_neighbors_of_vertex, neighbors_of_vertex, suffix_vertices)
    
    cdef bitset_s* parts_for_vertex = parts_for_vertices.rows[vertex]
    bitset_clear(parts_for_vertex)
    for part in range(parts_used):
        bitset_intersection(
            part_suffix_neighbors.rows[part],
            part_neighbors.rows[part],
            suffix_vertices
        )
        if bitset_issubset(part_suffix_neighbors.rows[part], suffix_neighbors_of_vertex):
            bitset_add(parts_for_vertex, part)

    for part in range(parts_used):
        if bitset_in(parts_for_vertex, part):
            for other_part in range(part):
                if bitset_in(parts_for_vertex, other_part):
                    if bitset_issubset(
                        part_suffix_neighbors.rows[part],
                        part_suffix_neighbors.rows[other_part]
                    ):
                        bitset_discard(parts_for_vertex, part)
                        break
                    elif bitset_issubset(
                        part_suffix_neighbors.rows[other_part],
                        part_suffix_neighbors.rows[part]
                    ):
                        bitset_discard(parts_for_vertex, other_part)
    
    return parts_for_vertex


cdef inline int _branch_adding_to_new_part(
    binary_matrix_t graph,
    int* prefix,
    int* part_of,
    int* parts_rename,
    int parts_used,
    bitset_t prefix_vertices,
    bitset_t suffix_vertices,
    binary_matrix_t new_suffixes,
    binary_matrix_t part_neighbors,
    binary_matrix_t previous_part_neighbors,
    binary_matrix_t parts_for_vertices,
    bitset_t suffix_neighbors_of_vertex,
    binary_matrix_t part_suffix_neighbors,
    bitset_t vertices_not_added,
    bitset_t canonical_vertices,
    int lower_bound,
    int upper_bound,
    int* best_order,
    int* best_partition,
    list solutions,
):
    cdef int level = _get_level(suffix_vertices)
    cdef int best_solution_found = -1
    cdef int part = parts_used - 1
    cdef bitset_t vertices = canonical_vertices if level == 0 else vertices_not_added
    cdef int vertex = bitset_next(vertices, 0)
    while vertex != -1:
        bitset_discard(suffix_vertices, vertex)
        prefix[level] = vertex

        current_solution = _branch_with_vertex_on_part(
            vertex,
            part,
            graph,
            prefix,
            part_of,
            parts_rename,
            parts_used,
            prefix_vertices,
            suffix_vertices,
            new_suffixes,
            part_neighbors,
            previous_part_neighbors,
            parts_for_vertices,
            suffix_neighbors_of_vertex,
            part_suffix_neighbors,
            vertices_not_added,
            canonical_vertices,
            lower_bound,
            upper_bound,
            best_order,
            best_partition,
            solutions,
        )

        if current_solution != -1:
            best_solution_found = current_solution
            upper_bound = best_solution_found
        
        bitset_add(suffix_vertices, vertex)
        vertex = bitset_next(vertices, vertex + 1)

    return best_solution_found


cdef inline int _branch_with_vertex_on_part(
    int vertex,
    int part,
    binary_matrix_t graph,
    int* prefix,
    int* part_of,
    int* parts_rename,
    int parts_used,
    bitset_t prefix_vertices,
    bitset_t suffix_vertices,
    binary_matrix_t new_suffixes,
    binary_matrix_t part_neighbors,
    binary_matrix_t previous_part_neighbors,
    binary_matrix_t parts_for_vertices,
    bitset_t suffix_neighbors_of_vertex,
    binary_matrix_t part_suffix_neighbors,
    bitset_t vertices_not_added,
    bitset_t canonical_vertices,
    int lower_bound,
    int upper_bound,
    int* best_order,
    int* best_partition,
    list solutions,
):
    part_of[vertex] = part

    _update_part_neighbors(
        part_neighbors.rows[part],
        previous_part_neighbors.rows[vertex],
        graph.rows[vertex]
    )

    cdef int solution = _branch_and_bound(
        graph,
        prefix,
        part_of,
        parts_rename,
        parts_used,
        prefix_vertices,
        suffix_vertices,
        new_suffixes,
        part_neighbors,
        previous_part_neighbors,
        parts_for_vertices,
        suffix_neighbors_of_vertex,
        part_suffix_neighbors,
        vertices_not_added,
        canonical_vertices,
        lower_bound,
        upper_bound,
        best_order,
        best_partition,
        solutions,
    )

    _undo_update_part_neighbors(
        part_neighbors.rows[part],
        previous_part_neighbors.rows[vertex]
    )

    return solution


cdef inline void _increment_prefix_greedily_on_existing_parts(
    binary_matrix_t graph,
    bitset_t suffix_vertices,
    int parts_used,
    int* prefix,
    int* part_of,
    binary_matrix_t part_neighbors,
    bitset_t suffix_neighbors_of_vertex,
    binary_matrix_t part_suffix_neighbors,
):
    """Add to prefix all vertices that have the same suffix neighbors as one of the parts."""
    cdef int level = _get_level(suffix_vertices)
    cdef int vertex
    cdef int part
    cdef bint suffix_changed = True
    while suffix_changed:
        suffix_changed = False
        vertex = bitset_next(suffix_vertices, 0)
        while vertex != -1:
            bitset_discard(suffix_vertices, vertex)

            part = _find_greedy_part_for_vertex(
                vertex,
                graph,
                suffix_vertices,
                parts_used,
                part_neighbors,
                suffix_neighbors_of_vertex,
                part_suffix_neighbors,
            )

            if part != -1:
                prefix[level] = vertex
                part_of[vertex] = part
                level += 1
                suffix_changed = True
            else:
                bitset_add(suffix_vertices, vertex)

            vertex = bitset_next(suffix_vertices, vertex + 1)


cdef inline bint _add_vertex_to_prefix_greedily_on_part(
    int part,
    binary_matrix_t graph,
    bitset_t prefix_vertices,
    bitset_t suffix_vertices,
    bitset_t suffix_neighbors_of_vertex,
    binary_matrix_t part_suffix_neighbors,
    int* prefix,
    int* part_of,
    binary_matrix_t part_neighbors,
):
    cdef int level = _get_level(suffix_vertices)
    cdef bint can_be_added
    cdef int vertex = bitset_next(suffix_vertices, 0)
    while vertex != -1:
        bitset_discard(suffix_vertices, vertex)

        bitset_intersection(
            suffix_neighbors_of_vertex, 
            graph.rows[vertex], 
            suffix_vertices
        )
        can_be_added = _is_greedy_part_for_vertex(
            part,
            suffix_vertices,
            part_neighbors,
            suffix_neighbors_of_vertex,
            part_suffix_neighbors,
        )

        if can_be_added:
            prefix[level] = vertex
            part_of[vertex] = part
            return True

        bitset_add(suffix_vertices, vertex)
        vertex = bitset_next(suffix_vertices, vertex + 1)
    
    return False 


cdef inline int _find_greedy_part_for_vertex(
    int vertex,
    binary_matrix_t graph,
    bitset_t suffix_vertices,
    int parts_used,
    binary_matrix_t part_neighbors,
    bitset_t suffix_neighbors_of_vertex,
    binary_matrix_t part_suffix_neighbors,
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
            part_suffix_neighbors,
        ):
            return part
    return -1


cdef inline bint _is_greedy_part_for_vertex(
    int part,
    bitset_t suffix_vertices,
    binary_matrix_t part_neighbors,
    bitset_t suffix_neighbors_of_vertex,
    binary_matrix_t part_suffix_neighbors,
):
    bitset_intersection(
        part_suffix_neighbors.rows[part],
        part_neighbors.rows[part],
        suffix_vertices
    )
    return bitset_eq(part_suffix_neighbors.rows[part], suffix_neighbors_of_vertex)


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

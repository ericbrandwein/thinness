from libc.stdint cimport uint64_t


cdef int search_words(
    const uint64_t* graph,
    int n,
    uint64_t canonical_vertices,
    int lower_bound,
    int upper_bound,
    int max_prefix_length,
    int max_seen_entries,
    int* best_order,
) except -2

# distutils: libraries = nautyL1
# distutils: include_dirs = /usr/include/nauty
"""Thinness and proper thinness of connected graphs with at most 11 vertices, for generating minimal graphs.

Graphs are stored as the neighbors of each vertex, in 64-bit words. Their
canonical form, computed with nauty, is the set of edges of the canonically
labelled graph, packed into a word with one bit per pair of vertices.

The values of the connected graphs of each order are kept in a table sorted by
canonical form, with one word per graph: its canonical form << 8 | its thinness
<< 4 | its proper thinness. So graphs can have at most 11 vertices, as 55 bits
of pairs plus 8 bits of values fit in a word.
"""
from libc.stdint cimport uint64_t
from libc.string cimport memcpy
from cysignals.memory cimport sig_malloc, sig_free

from thinness.branch_and_bound_64 cimport search_words as thinness_search
from proper_thinness.branch_and_bound_64 cimport search_words as proper_thinness_search


cdef extern from *:
    """
    #include <stdint.h>
    #define WORDSIZE 64
    #define MAXN WORDSIZE
    #include "nauty.h"

    static void check_nauty(int n) {
        nauty_check(WORDSIZE, 1, n, NAUTYVERSIONID);
    }

    /* The canonical form of the graph with the given neighbors, and the orbits of its automorphism group. */
    static uint64_t canonical_form(const uint64_t* neighbors, int n, int* orbits) {
        graph g[MAXN], canonical[MAXN];
        int lab[MAXN], ptn[MAXN];
        static DEFAULTOPTIONS_GRAPH(options);
        statsblk stats;
        options.getcanon = TRUE;
        for (int i = 0; i < n; i++) {
            g[i] = 0;
            for (int j = 0; j < n; j++)
                if ((neighbors[i] >> j) & 1)
                    ADDELEMENT(GRAPHROW(g, i, 1), j);
        }
        densenauty(g, lab, ptn, orbits, &options, &stats, 1, n, canonical);
        uint64_t form = 0;
        int pair = 0;
        for (int j = 1; j < n; j++)
            for (int i = 0; i < j; i++, pair++)
                if (ISELEMENT(GRAPHROW(canonical, i, 1), j))
                    form |= (uint64_t)1 << pair;
        return form;
    }
    """
    void check_nauty(int n)
    uint64_t canonical_form(const uint64_t* neighbors, int n, int* orbits)


cdef extern from *:
    int __builtin_ctzll(unsigned long long) nogil


cdef enum:
    _MAX_ORDER = 11

MAX_ORDER = _MAX_ORDER
# The searches are small, so the memo never needs to be large.
cdef int MAX_SEEN_ENTRIES = 100_000

check_nauty(_MAX_ORDER)


# PROFILING: seconds and calls of each stage of `classify`, and how many searches found no solution.
from posix.time cimport clock_gettime, timespec, CLOCK_MONOTONIC

cdef enum:
    STAGE_CANONICAL_FORM
    STAGE_SMALLER_GRAPHS
    STAGE_THINNESS_SEARCH
    STAGE_PROPER_THINNESS_SEARCH
    STAGE_PROPER_THINNESS_SECOND_SEARCH
    STAGES

STAGE_NAMES = [
    'canonical form', 'smaller graphs', 'thinness search',
    'proper thinness search', 'proper thinness second search',
]
cdef double _seconds[STAGES]
cdef long _calls[STAGES]
cdef long _failures[STAGES]


cdef inline double _now() noexcept:
    cdef timespec time
    clock_gettime(CLOCK_MONOTONIC, &time)
    return time.tv_sec + time.tv_nsec * 1e-9


cdef inline double _record(int stage, double start) noexcept:
    cdef double now = _now()
    _seconds[stage] += now - start
    _calls[stage] += 1
    return now


def stage_stats() -> list[tuple[str, float, int, int]]:
    """The name, seconds, calls and searches without solution of each stage."""
    return [(STAGE_NAMES[stage], _seconds[stage], _calls[stage], _failures[stage]) for stage in range(STAGES)]


def canonical_form_of_graph6(bytes graph6) -> tuple[int, int]:
    """The order and the canonical form of the graph."""
    cdef uint64_t neighbors[_MAX_ORDER]
    cdef int orbits[_MAX_ORDER]
    cdef int n = _decode_graph6(graph6, neighbors)
    return n, canonical_form(neighbors, n, orbits)


cdef class Classifier:
    """Computes the values of connected graphs from the tables of the smaller orders."""
    cdef uint64_t* tables[_MAX_ORDER + 1]
    cdef size_t table_sizes[_MAX_ORDER + 1]

    def __cinit__(self, dict tables):
        """`tables` maps orders to the bytes of their tables.

        Graphs of order n need the tables of every order below n.
        """
        cdef int order
        cdef bytes table
        for order in range(_MAX_ORDER + 1):
            self.tables[order] = NULL
            self.table_sizes[order] = 0
        for order, table in tables.items():
            if not 1 <= order <= _MAX_ORDER:
                raise ValueError(f'Tables must be of orders 1 to {MAX_ORDER}')
            self.tables[order] = <uint64_t*>sig_malloc(max(len(table), 1))
            if self.tables[order] == NULL:
                raise MemoryError
            memcpy(self.tables[order], <const char*>table, len(table))
            self.table_sizes[order] = len(table) // sizeof(uint64_t)

    def __dealloc__(self):
        cdef int order
        for order in range(_MAX_ORDER + 1):
            sig_free(self.tables[order])

    def classify(self, bytes graph6) -> tuple[int, int, int, int, int]:
        """The canonical form, thinness and proper thinness of the connected graph, and the largest ones without a vertex.

        The graph is minimal for a parameter if its value is larger than the
        largest one without a vertex.
        """
        cdef uint64_t neighbors[_MAX_ORDER]
        cdef int orbits[_MAX_ORDER]
        cdef double start = _now()  # PROFILING
        cdef int n = _decode_graph6(graph6, neighbors)
        cdef uint64_t form = canonical_form(neighbors, n, orbits)
        cdef uint64_t canonical_vertices = 0
        cdef int vertex
        for vertex in range(n):
            if orbits[vertex] == vertex:
                canonical_vertices |= _bit(vertex)
        start = _record(STAGE_CANONICAL_FORM, start)  # PROFILING

        cdef int largest_thinness = 0
        cdef int largest_proper_thinness = 0
        cdef int values
        for vertex in range(n):
            values = self._values_without_vertex(neighbors, n, vertex)
            largest_thinness = max(largest_thinness, values >> 4)
            largest_proper_thinness = max(largest_proper_thinness, values & 15)
        start = _record(STAGE_SMALLER_GRAPHS, start)  # PROFILING

        cdef int thinness = 1
        cdef int proper_thinness = 1
        cdef int lower_bound
        if n > 1:
            # Removing a vertex lowers the thinness by at most one, as putting it
            # first in a part of its own gives a solution.
            thinness = thinness_search(
                neighbors, n, canonical_vertices,
                largest_thinness, largest_thinness, n, MAX_SEEN_ENTRIES,
            )
            if thinness == -1:
                thinness = largest_thinness + 1
                _failures[STAGE_THINNESS_SEARCH] += 1  # PROFILING
            start = _record(STAGE_THINNESS_SEARCH, start)  # PROFILING

            # It can lower the proper thinness by more than one (see the README),
            # so if the bound isn't reached, the search looks for the best solution.
            lower_bound = max(thinness, largest_proper_thinness)
            proper_thinness = proper_thinness_search(
                neighbors, n, canonical_vertices,
                lower_bound, lower_bound, n, MAX_SEEN_ENTRIES,
            )
            if proper_thinness == -1:
                _failures[STAGE_PROPER_THINNESS_SEARCH] += 1  # PROFILING
            start = _record(STAGE_PROPER_THINNESS_SEARCH, start)  # PROFILING
            if proper_thinness == -1:
                proper_thinness = proper_thinness_search(
                    neighbors, n, canonical_vertices,
                    lower_bound + 1, n, n, MAX_SEEN_ENTRIES,
                )
                start = _record(STAGE_PROPER_THINNESS_SECOND_SEARCH, start)  # PROFILING
            if proper_thinness == -1:
                raise RuntimeError(f'No proper thinness found for {graph6}')

        return form, thinness, proper_thinness, largest_thinness, largest_proper_thinness

    cdef int _values_without_vertex(self, const uint64_t* neighbors, int n, int vertex) except -1:
        """The values of the graph without `vertex`, as thinness << 4 | proper thinness.

        They are the largest ones of its components.
        """
        cdef uint64_t remaining = _lower_bits(n) & ~_bit(vertex)
        cdef uint64_t component
        cdef uint64_t frontier
        cdef uint64_t added
        cdef uint64_t component_neighbors[_MAX_ORDER]
        cdef int orbits[_MAX_ORDER]
        cdef int thinness = 0
        cdef int proper_thinness = 0
        cdef int order
        cdef int values
        cdef int u
        while remaining != 0:
            component = remaining & (~remaining + 1)
            frontier = component
            while frontier != 0:
                u = __builtin_ctzll(frontier)
                frontier &= frontier - 1
                added = neighbors[u] & remaining & ~component
                component |= added
                frontier |= added
            remaining &= ~component

            order = _induced_subgraph(neighbors, component, component_neighbors)
            values = self._lookup(order, canonical_form(component_neighbors, order, orbits))
            thinness = max(thinness, values >> 4)
            proper_thinness = max(proper_thinness, values & 15)
        return thinness << 4 | proper_thinness

    cdef int _lookup(self, int order, uint64_t form) except -1:
        """The values of a connected graph in the table of its order, by binary search."""
        cdef const uint64_t* table = self.tables[order]
        cdef size_t size = self.table_sizes[order]
        cdef uint64_t key = form << 8
        cdef size_t low = 0
        cdef size_t high = size
        cdef size_t middle
        while low < high:
            middle = (low + high) // 2
            if table[middle] < key:
                low = middle + 1
            else:
                high = middle
        if low == size or table[low] >> 8 != form:
            raise KeyError(f'Graph of order {order} not in the tables')
        return table[low] & 0xff


cdef int _induced_subgraph(const uint64_t* neighbors, uint64_t vertices, uint64_t* subgraph_neighbors) noexcept:
    """Writes the neighbors of the subgraph induced by `vertices`, relabelled in order from 0, and returns its order."""
    cdef int position[_MAX_ORDER]
    cdef int order = 0
    cdef uint64_t rest = vertices
    cdef uint64_t vertex_neighbors
    cdef int u
    cdef int w
    while rest != 0:
        u = __builtin_ctzll(rest)
        rest &= rest - 1
        position[u] = order
        order += 1
    rest = vertices
    while rest != 0:
        u = __builtin_ctzll(rest)
        rest &= rest - 1
        subgraph_neighbors[position[u]] = 0
        vertex_neighbors = neighbors[u] & vertices
        while vertex_neighbors != 0:
            w = __builtin_ctzll(vertex_neighbors)
            vertex_neighbors &= vertex_neighbors - 1
            subgraph_neighbors[position[u]] |= _bit(position[w])
    return order


cdef int _decode_graph6(bytes graph6, uint64_t* neighbors) except -1:
    """Writes the neighbors of each vertex of the graph and returns its order.

    Anything after the graph, such as a newline, is ignored.
    """
    cdef const unsigned char* data = <const unsigned char*><const char*>graph6
    cdef Py_ssize_t length = len(graph6)
    if length == 0:
        raise ValueError('Empty graph6')
    cdef int n = data[0] - 63
    if not 1 <= n <= _MAX_ORDER:
        raise ValueError(f'Graphs must have 1 to {MAX_ORDER} vertices')
    cdef int pairs = n * (n - 1) // 2
    if length < 1 + (pairs + 5) // 6:
        raise ValueError(f'Truncated graph6: {graph6}')

    cdef int i
    cdef int j
    cdef int pair = 0
    for i in range(n):
        neighbors[i] = 0
    for j in range(1, n):
        for i in range(j):
            if ((data[1 + pair // 6] - 63) >> (5 - pair % 6)) & 1:
                neighbors[i] |= _bit(j)
                neighbors[j] |= _bit(i)
            pair += 1
    return n


cdef inline uint64_t _bit(int i) noexcept:
    return (<uint64_t>1) << i


cdef inline uint64_t _lower_bits(int n) noexcept:
    """The set {0, ..., n-1}."""
    return _bit(n) - 1

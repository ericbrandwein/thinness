# distutils: libraries = nautyL1
# distutils: include_dirs = /usr/include/nauty
"""Thinness and proper thinness of connected graphs with at most 11 vertices, for generating minimal graphs.

Graphs are stored as the neighbors of each vertex, in 64-bit words. Their
canonical form, computed with nauty, is the set of edges of the canonically
labelled graph, packed into a word with one bit per pair of vertices.

The connected graphs of each order are kept in a table sorted by canonical form,
with two words per graph:
- its canonical form << 8 | its thinness << 4 | its proper thinness. So graphs
  can have at most 11 vertices, as 55 bits of pairs plus 8 bits of values fit
  in a word.
- the order of an optimal solution for its proper thinness, with 4 bits per
  vertex, which is its canonical label: its position in the canonically
  labelled graph. So it is an order of any graph with the same canonical form.
"""
from libc.stdint cimport uint64_t
from libc.string cimport memcpy

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

    /* The canonical form of the graph with the given neighbors, the orbits of its
       automorphism group, and the vertex of each canonical label. */
    static uint64_t canonical_form(const uint64_t* neighbors, int n, int* orbits, int* labelling) {
        graph g[MAXN], canonical[MAXN];
        int ptn[MAXN];
        static DEFAULTOPTIONS_GRAPH(options);
        statsblk stats;
        options.getcanon = TRUE;
        for (int i = 0; i < n; i++) {
            g[i] = 0;
            for (int j = 0; j < n; j++)
                if ((neighbors[i] >> j) & 1)
                    ADDELEMENT(GRAPHROW(g, i, 1), j);
        }
        densenauty(g, labelling, ptn, orbits, &options, &stats, 1, n, canonical);
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
    uint64_t canonical_form(const uint64_t* neighbors, int n, int* orbits, int* labelling)


cdef extern from *:
    int __builtin_ctzll(unsigned long long) nogil


cdef enum:
    _MAX_ORDER = 11
    _MAX_ORDER_SQUARED = 121

MAX_ORDER = _MAX_ORDER
# The searches are small, so the memo never needs to be large.
cdef int MAX_SEEN_ENTRIES = 100_000

check_nauty(_MAX_ORDER)


def canonical_form_of_graph6(bytes graph6) -> tuple[int, int]:
    """The order and the canonical form of the graph."""
    cdef uint64_t neighbors[_MAX_ORDER]
    cdef int orbits[_MAX_ORDER]
    cdef int labelling[_MAX_ORDER]
    cdef int n = _decode_graph6(graph6, neighbors)
    return n, canonical_form(neighbors, n, orbits, labelling)


cdef class Classifier:
    """Computes the values of connected graphs from the tables of the smaller orders."""
    cdef uint64_t* tables[_MAX_ORDER + 1]
    cdef size_t table_sizes[_MAX_ORDER + 1]
    # The objects holding the tables, kept alive while their memory is used.
    cdef list buffers

    def __cinit__(self, dict tables):
        """`tables` maps orders to buffers with their tables, such as memory maps of their files.

        Graphs of order n need the tables of every order below n.
        """
        cdef int order
        cdef const unsigned char[::1] view
        for order in range(_MAX_ORDER + 1):
            self.tables[order] = NULL
            self.table_sizes[order] = 0
        self.buffers = []
        for order, table in tables.items():
            if not 1 <= order <= _MAX_ORDER:
                raise ValueError(f'Tables must be of orders 1 to {MAX_ORDER}')
            view = table
            if view.shape[0] == 0 or view.shape[0] % (2 * sizeof(uint64_t)) != 0:
                raise ValueError(f'The table of order {order} has a wrong size')
            self.buffers.append(table)
            # They are never written to.
            self.tables[order] = <uint64_t*>&view[0]
            self.table_sizes[order] = view.shape[0] // (2 * sizeof(uint64_t))

    def classify(self, bytes graph6) -> tuple[int, int, int, int, int, int]:
        """The two words of the connected graph in its table, its thinness and proper thinness, and the largest ones without a vertex.

        The graph is minimal for a parameter if its value is larger than the
        largest one without a vertex.
        """
        cdef uint64_t neighbors[_MAX_ORDER]
        cdef int orbits[_MAX_ORDER]
        cdef int labelling[_MAX_ORDER]
        cdef int n = _decode_graph6(graph6, neighbors)
        cdef uint64_t form = canonical_form(neighbors, n, orbits, labelling)
        cdef uint64_t canonical_vertices = 0
        cdef int vertex
        for vertex in range(n):
            if orbits[vertex] == vertex:
                canonical_vertices |= _bit(vertex)

        # The order of an optimal solution without each vertex, one after the other.
        cdef int orders_without_vertex[_MAX_ORDER_SQUARED]
        cdef int largest_thinness = 0
        cdef int largest_proper_thinness = 0
        cdef int values
        for vertex in range(n):
            values = self._values_without_vertex(neighbors, n, vertex, orders_without_vertex + vertex * (n - 1))
            largest_thinness = max(largest_thinness, values >> 4)
            largest_proper_thinness = max(largest_proper_thinness, values & 15)

        cdef int thinness = 1
        cdef int proper_thinness = 1
        cdef int best_order[_MAX_ORDER]
        cdef int lower_bound
        cdef int heuristic_proper_thinness
        best_order[0] = 0
        if n > 1:
            # Removing a vertex lowers the thinness by at most one, as putting it
            # first in a part of its own gives a solution.
            thinness = thinness_search(
                neighbors, n, canonical_vertices,
                largest_thinness, largest_thinness, n, MAX_SEEN_ENTRIES,
            )
            if thinness == -1:
                thinness = largest_thinness + 1

            # It can lower the proper thinness by more than one (see the README), so
            # the bound may not be reached. But it almost always is, and the
            # heuristic usually finds such a solution much faster than the search.
            lower_bound = max(thinness, largest_proper_thinness)
            heuristic_proper_thinness = _insertion_heuristic(
                neighbors, n, orders_without_vertex, lower_bound, best_order,
            )
            proper_thinness = heuristic_proper_thinness
            if heuristic_proper_thinness > lower_bound:
                proper_thinness = proper_thinness_search(
                    neighbors, n, canonical_vertices,
                    lower_bound, heuristic_proper_thinness - 1, n, MAX_SEEN_ENTRIES, best_order,
                )
                if proper_thinness == -1:
                    proper_thinness = heuristic_proper_thinness

        return (
            form << 8 | thinness << 4 | proper_thinness,
            _pack_order(best_order, n, labelling),
            thinness,
            proper_thinness,
            largest_thinness,
            largest_proper_thinness,
        )

    cdef int _values_without_vertex(self, const uint64_t* neighbors, int n, int vertex, int* order) except -1:
        """The values of the graph without `vertex`, as thinness << 4 | proper thinness.

        They are the largest ones of its components. The optimal orders of the
        components for the proper thinness are written to `order` one after the
        other, which is an optimal order of the graph, as there are no conflicts
        between vertices of different components.
        """
        cdef uint64_t remaining = _lower_bits(n) & ~_bit(vertex)
        cdef uint64_t component
        cdef uint64_t frontier
        cdef uint64_t added
        cdef uint64_t component_neighbors[_MAX_ORDER]
        cdef int component_vertices[_MAX_ORDER]
        cdef int orbits[_MAX_ORDER]
        cdef int labelling[_MAX_ORDER]
        cdef uint64_t packed_order
        cdef int thinness = 0
        cdef int proper_thinness = 0
        cdef int length = 0
        cdef int component_order
        cdef int values
        cdef int u
        cdef int i
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

            component_order = _induced_subgraph(neighbors, component, component_neighbors, component_vertices)
            values = self._lookup(
                component_order,
                canonical_form(component_neighbors, component_order, orbits, labelling),
                &packed_order,
            )
            thinness = max(thinness, values >> 4)
            proper_thinness = max(proper_thinness, values & 15)
            for i in range(component_order):
                order[length] = component_vertices[labelling[(packed_order >> (4 * i)) & 15]]
                length += 1
        return thinness << 4 | proper_thinness

    cdef int _lookup(self, int order, uint64_t form, uint64_t* packed_order) except -1:
        """The values of a connected graph in the table of its order, by binary search, and its packed order."""
        cdef const uint64_t* table = self.tables[order]
        cdef size_t size = self.table_sizes[order]
        cdef uint64_t key = form << 8
        cdef size_t low = 0
        cdef size_t high = size
        cdef size_t middle
        while low < high:
            middle = (low + high) // 2
            if table[2 * middle] < key:
                low = middle + 1
            else:
                high = middle
        if low == size or table[2 * low] >> 8 != form:
            raise KeyError(f'Graph of order {order} not in the tables')
        packed_order[0] = table[2 * low + 1]
        return table[2 * low] & 0xff


cdef int _insertion_heuristic(
    const uint64_t* neighbors,
    int n,
    const int* orders_without_vertex,
    int lower_bound,
    int* best_order,
) noexcept:
    """The fewest parts of a solution for the proper thinness among the orders with each vertex inserted in the order without it.

    It stops when one reaches `lower_bound`, and writes the best order found to
    `best_order`. Some optimal order of the graph is one without a vertex with that
    vertex inserted somewhere, so these orders often reach the proper thinness.
    """
    # Any order has a solution with a part for each vertex.
    cdef int best = n
    cdef int order[_MAX_ORDER]
    cdef const int* order_without_vertex
    cdef int vertex
    cdef int position
    cdef int parts
    for vertex in range(n):
        best_order[vertex] = vertex
    for vertex in range(n):
        order_without_vertex = orders_without_vertex + vertex * (n - 1)
        order[0] = vertex
        memcpy(order + 1, order_without_vertex, (n - 1) * sizeof(int))
        for position in range(n):
            if position > 0:
                # Moves the vertex one position later.
                order[position - 1] = order_without_vertex[position - 1]
                order[position] = vertex
            parts = _proper_parts_for_order(neighbors, n, order)
            if parts < best:
                best = parts
                memcpy(best_order, order, n * sizeof(int))
                if best <= lower_bound:
                    return best
    return best


cdef uint64_t _pack_order(const int* order, int n, const int* labelling) noexcept:
    """The order as the canonical label of each vertex, with 4 bits each."""
    cdef int canonical_label[_MAX_ORDER]
    cdef uint64_t packed = 0
    cdef int i
    for i in range(n):
        canonical_label[labelling[i]] = i
    for i in range(n):
        packed |= (<uint64_t>canonical_label[order[i]]) << (4 * i)
    return packed


cdef int _proper_parts_for_order(const uint64_t* neighbors, int n, const int* order) noexcept:
    """The fewest parts of a solution for the proper thinness consistent with `order`.

    Same as `proper_thinness.heuristic.solution_from_order`, without the partition:
    the positions minus a maximum matching between earlier and later positions
    that don't conflict.
    """
    cdef int position[_MAX_ORDER]
    cdef uint64_t ordered_neighbors[_MAX_ORDER]
    cdef uint64_t compatible_later[_MAX_ORDER]
    cdef int previous[_MAX_ORDER]
    cdef uint64_t vertex_neighbors
    cdef uint64_t visited
    cdef int i
    cdef int j
    cdef int matched = 0
    for i in range(n):
        position[order[i]] = i
    for i in range(n):
        ordered_neighbors[i] = 0
        vertex_neighbors = neighbors[order[i]]
        while vertex_neighbors != 0:
            ordered_neighbors[i] |= _bit(position[__builtin_ctzll(vertex_neighbors)])
            vertex_neighbors &= vertex_neighbors - 1

    # The positions i < j conflict if some vertex after j is adjacent to the one
    # at i but not to the one at j, or some vertex before i is adjacent to the one
    # at j but not to the one at i.
    for i in range(n):
        compatible_later[i] = 0
        for j in range(i + 1, n):
            if (
                ordered_neighbors[i] & ~ordered_neighbors[j] & ~_lower_bits(j + 1) == 0
                and ordered_neighbors[j] & ~ordered_neighbors[i] & _lower_bits(i) == 0
            ):
                compatible_later[i] |= _bit(j)

    for i in range(n):
        previous[i] = -1
    for i in range(n):
        visited = 0
        if _augment(i, compatible_later, previous, &visited):
            matched += 1
    return n - matched


cdef bint _augment(int position, const uint64_t* compatible_later, int* previous, uint64_t* visited) noexcept:
    """Whether an augmenting path from `position` was found, in which case it is applied to `previous`."""
    cdef uint64_t candidates = compatible_later[position]
    cdef int next_position
    while candidates != 0:
        next_position = __builtin_ctzll(candidates)
        candidates &= candidates - 1
        if visited[0] & _bit(next_position):
            continue
        visited[0] |= _bit(next_position)
        if previous[next_position] == -1 or _augment(previous[next_position], compatible_later, previous, visited):
            previous[next_position] = position
            return True
    return False


cdef int _induced_subgraph(
    const uint64_t* neighbors,
    uint64_t vertices,
    uint64_t* subgraph_neighbors,
    int* subgraph_vertices,
) noexcept:
    """Writes the neighbors of the subgraph induced by `vertices`, relabelled in order from 0, and returns its order.

    The vertex of the graph with each label of the subgraph is written to `subgraph_vertices`.
    """
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
        subgraph_vertices[order] = u
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

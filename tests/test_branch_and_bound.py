import unittest
import unittest.mock
import itertools

from sage.graphs.graph import Graph
from sage.graphs.graph_generators import graphs
from sage.misc.randstate import set_random_seed

from thinness import branch_and_bound
from thinness.branch_and_bound import calculate_thinness
from thinness.optimizations import ALL_OPTIMIZATIONS, Optimization
from thinness.z3 import Z3ThinnessSolver
from thinness.verify import verify_solution
from thinness.shower import show_graph, show_solution

class TestBranchAndBound(unittest.TestCase):
    def _assert_thinness_of_graph(self, graph: Graph, expected_thinness: int):
        actual_thinness = calculate_thinness(graph)
        self.assertEqual(actual_thinness, expected_thinness)
        solution = calculate_thinness(graph, certificate=True)
        self.assertEqual(solution.thinness, expected_thinness)
        self.assertTrue(verify_solution(graph, solution))

    def _assert_thinness_with_optimizations(self, graph: Graph, expected_thinness: int, optimizations: Optimization):
        self.assertEqual(calculate_thinness(graph, optimizations=optimizations), expected_thinness)
        solution = calculate_thinness(graph, certificate=True, optimizations=optimizations)
        self.assertEqual(solution.thinness, expected_thinness)
        self.assertTrue(verify_solution(graph, solution))

    def test_thinness_of_K1(self):
        self._assert_thinness_of_graph(Graph(1), 1)

    def test_thinness_of_K2(self):
        self._assert_thinness_of_graph(graphs.CompleteGraph(2), 1)
        
    def test_thinness_of_independent_graph(self):
        self._assert_thinness_of_graph(Graph(5), 1)
        
    def test_thinness_of_K3(self):
        self._assert_thinness_of_graph(graphs.CompleteGraph(3), 1)
    
    def test_thinness_of_cycle(self):
        self._assert_thinness_of_graph(graphs.CycleGraph(4), 2)

    def test_graph_that_segfaults(self):
        graph = Graph(r'J?AADI\x\z_')
        calculate_thinness(graph)

    def test_crown_graphs(self):
        for n in range(2, 10):
            graph = crown_graph(n)
            thinness = n - 1
            with self.subTest(graph=graph.graph6_string()):
                self._assert_thinness_of_graph(graph, thinness)

    def test_complement_of_nK2(self):
        for n in range(1, 10):
            graph = (graphs.CompleteGraph(2) * n).complement()
            thinness = n
            with self.subTest(graph=graph.graph6_string()):
                self._assert_thinness_of_graph(graph, thinness)

    def test_thinness_of_random_graphs(self):
        set_random_seed(0)
        n = 8
        solver = Z3ThinnessSolver(n)
        for _ in range(100):
            graph = graphs.RandomGNP(n, 0.5)
            thinness = solver.solve(graph).thinness
            with self.subTest(graph=graph.graph6_string()):
                self._assert_thinness_of_graph(graph, thinness)

    def test_thinness_of_random_graphs_against_reference(self):
        set_random_seed(0)
        for n in range(9, 14):
            for density in [0.2, 0.5, 0.8]:
                for _ in range(10):
                    graph = graphs.RandomGNP(n, density)
                    thinness = reference_thinness(graph)
                    with self.subTest(graph=graph.graph6_string()):
                        self._assert_thinness_of_graph(graph, thinness)
                        self.assertEqual(calculate_thinness(graph, max_seen_entries=0), thinness)

    def test_upper_bound_of_random_graphs(self):
        set_random_seed(0)
        for _ in range(20):
            graph = graphs.RandomGNP(11, 0.6)
            thinness = reference_thinness(graph)
            with self.subTest(graph=graph.graph6_string()):
                self.assertEqual(calculate_thinness(graph, upper_bound=thinness + 1), thinness)
                self.assertEqual(calculate_thinness(graph, upper_bound=thinness), thinness)

    def test_thinness_of_disconnected_graphs(self):
        # The largest component doesn't have the largest thinness.
        self._assert_thinness_of_graph(graphs.PathGraph(10) + crown_graph(4), 3)
        self._assert_thinness_of_graph(crown_graph(4) + graphs.PathGraph(10) + crown_graph(3), 3)

    def test_thinness_of_random_disconnected_graphs(self):
        set_random_seed(0)
        for _ in range(20):
            graph = graphs.RandomGNP(8, 0.6) + graphs.RandomGNP(6, 0.5) + graphs.RandomGNP(4, 0.7)
            thinness = reference_thinness(graph)
            with self.subTest(graph=graph.graph6_string()):
                self._assert_thinness_of_graph(graph, thinness)

    def test_thinness_of_random_graphs_with_bitsets_against_reference(self):
        # Graphs this small are searched with 64-bit words, so force the search with bitsets.
        set_random_seed(0)
        with unittest.mock.patch.object(branch_and_bound, 'MAX_VERTICES_FOR_WORDS', 0):
            for n in range(9, 12):
                for density in [0.2, 0.5, 0.8]:
                    for _ in range(5):
                        graph = graphs.RandomGNP(n, density)
                        thinness = reference_thinness(graph)
                        with self.subTest(graph=graph.graph6_string()):
                            self._assert_thinness_of_graph(graph, thinness)

    def test_thinness_without_each_optimization(self):
        set_random_seed(0)
        for graph in _graphs_for_optimizations(orders=[8, 10], graphs_per_case=3):
            thinness = reference_thinness(graph)
            for optimization in Optimization:
                with self.subTest(graph=graph.graph6_string(), without=optimization.name):
                    self._assert_thinness_with_optimizations(graph, thinness, ALL_OPTIMIZATIONS & ~optimization)

    def test_statistics_count_the_nodes_searched(self):
        statistics = {}
        calculate_thinness(crown_graph(4), statistics=statistics)
        self.assertGreater(statistics['nodes'], 0)

    def test_thinness_without_optimizations(self):
        set_random_seed(0)
        for graph in _graphs_for_optimizations(orders=[6, 7], graphs_per_case=3):
            thinness = reference_thinness(graph)
            with self.subTest(graph=graph.graph6_string()):
                self._assert_thinness_with_optimizations(graph, thinness, Optimization(0))

    def test_thinness_without_each_optimization_with_bitsets(self):
        # Graphs this small are searched with 64-bit words, so force the search with bitsets.
        set_random_seed(0)
        with unittest.mock.patch.object(branch_and_bound, 'MAX_VERTICES_FOR_WORDS', 0):
            for graph in _graphs_for_optimizations(orders=[8], graphs_per_case=2):
                thinness = reference_thinness(graph)
                for optimizations in [ALL_OPTIMIZATIONS & ~optimization for optimization in Optimization] + [Optimization(0)]:
                    with self.subTest(graph=graph.graph6_string(), optimizations=optimizations):
                        self._assert_thinness_with_optimizations(graph, thinness, optimizations)

    def test_thinness_of_graph_with_more_than_64_vertices(self):
        self._assert_thinness_of_graph(graphs.CycleGraph(70), 2)

    def test_thinness_of_join(self):
        graph = Graph('GCOf?w')
        self._assert_thinness_of_graph(graph, 2)
        joined_graph = graph.join(Graph(1), labels='integers')
        self._assert_thinness_of_graph(joined_graph, 2)

    def test_thinness_of_induced_subgraphs(self):
        first = Graph(r'Mi\rzx?OA@gEONON?')
        second = Graph(r'Si\rzx?OA@gEONONG?A??O?L??q?@y?@w')
        self.assertTrue(first.is_subgraph(second, induced=True, up_to_isomorphism=True))
        self.assertGreaterEqual(calculate_thinness(second), calculate_thinness(first))
        self._assert_thinness_of_graph(first, 3)


def _graphs_for_optimizations(orders: list[int], graphs_per_case: int) -> list[Graph]:
    """Random graphs of each order and density, and a disconnected one for `Optimization.COMPONENTS`."""
    random_graphs = [
        graphs.RandomGNP(n, density)
        for n in orders
        for density in [0.3, 0.5, 0.8]
        for _ in range(graphs_per_case)
    ]
    random_graphs.append(graphs.RandomGNP(orders[0] - 2, 0.5) + crown_graph(3))
    return random_graphs


def crown_graph(vertices_per_side: int) -> Graph:
    graph = Graph(2*vertices_per_side)
    for u, v in itertools.permutations(range(vertices_per_side), 2):
        graph.add_edge(u, v + vertices_per_side)
    return graph


def reference_thinness(graph: Graph) -> int:
    """Thinness computed by a plain search without any of the pruning rules of the branch and bound.

    Builds the order vertex by vertex, trying every vertex of the suffix on every
    part it can be added to. Only remembers the states already searched, where a
    state is the suffix and the suffix neighbors of each part.
    """
    graph = graph.relabel(inplace=False)
    n = graph.order()
    neighbors = [sum(1 << neighbor for neighbor in graph.neighbor_iterator(vertex)) for vertex in range(n)]
    for max_parts in itertools.count(1):
        if _has_consistent_solution(n, neighbors, max_parts):
            return max_parts


def _has_consistent_solution(n: int, neighbors: list[int], max_parts: int) -> bool:
    seen_states = set()

    def extend(suffix: int, part_neighbors: tuple[int, ...]) -> bool:
        if suffix == 0:
            return True
        if (suffix, part_neighbors) in seen_states:
            return False
        seen_states.add((suffix, part_neighbors))
        for vertex in range(n):
            if not suffix >> vertex & 1:
                continue
            new_suffix = suffix & ~(1 << vertex)
            vertex_neighbors = neighbors[vertex] & new_suffix
            new_part_neighbors = [neighbors_of_part & new_suffix for neighbors_of_part in part_neighbors]
            for part in range(len(part_neighbors) + 1):
                if part == len(part_neighbors):
                    if part == max_parts:
                        continue
                    parts = new_part_neighbors + [vertex_neighbors]
                elif new_part_neighbors[part] & ~vertex_neighbors == 0:
                    parts = list(new_part_neighbors)
                    parts[part] = vertex_neighbors
                else:
                    continue
                if extend(new_suffix, tuple(sorted(parts))):
                    return True
        return False

    return extend((1 << n) - 1, ())
import unittest
import unittest.mock
import itertools

from sage.graphs.graph import Graph
from sage.graphs.graph_generators import graphs
from sage.misc.randstate import set_random_seed

from proper_thinness import branch_and_bound
from proper_thinness.branch_and_bound import calculate_proper_thinness
from thinness.z3 import Z3ProperThinnessSolver
from proper_thinness.verify import verify_solution

class TestBranchAndBound(unittest.TestCase):
    def _assert_proper_thinness_of_graph(self, graph: Graph, expected_proper_thinness: int):
        actual_proper_thinness = calculate_proper_thinness(graph)
        self.assertEqual(actual_proper_thinness, expected_proper_thinness)
        solution = calculate_proper_thinness(graph, certificate=True)
        self.assertEqual(solution.thinness, expected_proper_thinness)
        if not verify_solution(graph, solution):
            print("Graph:", graph.graph6_string())
            print("Solution order:", solution.order)
            print("Solution partition:", solution.partition)
        self.assertTrue(verify_solution(graph, solution))

    def test_proper_thinness_of_K1(self):
        self._assert_proper_thinness_of_graph(Graph(1), 1)

    def test_proper_thinness_of_K2(self):
        self._assert_proper_thinness_of_graph(graphs.CompleteGraph(2), 1)
        
    def test_proper_thinness_of_independent_graph(self):
        self._assert_proper_thinness_of_graph(Graph(5), 1)
        
    def test_proper_thinness_of_K3(self):
        self._assert_proper_thinness_of_graph(graphs.CompleteGraph(3), 1)
    
    def test_proper_thinness_of_cycle(self):
        self._assert_proper_thinness_of_graph(graphs.CycleGraph(4), 2)

    def test_graph_that_segfaults(self):
        graph = Graph(r'J?AADI\x\z_')
        calculate_proper_thinness(graph)

    def test_proper_thinness_of_small_graph(self):
        graph = Graph(r'CN')
        self._assert_proper_thinness_of_graph(graph, 1)

    def test_proper_thinness_of_graph_with_7_vertices(self):
        graph = Graph(r'FcBuw')
        self._assert_proper_thinness_of_graph(graph, 2)

    def test_proper_thinness_of_claw(self):
        graph = graphs.ClawGraph()
        self._assert_proper_thinness_of_graph(graph, 2)

    def test_proper_thinness_of_double_claw(self):
        graph = Graph(r'LsPA@?_G?_A?C?')
        self._assert_proper_thinness_of_graph(graph, 3)

    @unittest.skip("This test is too slow")
    def test_proper_thinness_of_triple_claw(self):
        graph = Graph(r'gsPA@?_G?_A?C?A?@??O?@??C??G??C??A???_??A???G???O???G???C???@????C????O????_????O????G????A?????G?????_????@??????_?????O?????C????')
        self._assert_proper_thinness_of_graph(graph, 4)

    def test_proper_thinness_of_forbidden_induced_subgraph_of_trivially_perfect_graphs_of_pthin_2(self):
        graph = Graph(r'J}qCKIC~{??')
        self._assert_proper_thinness_of_graph(graph, 3)

    def test_proper_thinness_of_random_graphs(self):
        set_random_seed(0)
        n = 7
        solver = Z3ProperThinnessSolver(n)
        for _ in range(100):
            graph = graphs.RandomGNP(n, 0.5)
            solution = solver.solve(graph)
            with self.subTest(graph=graph.graph6_string()):
                self._assert_proper_thinness_of_graph(graph, solution.thinness)

    def test_proper_thinness_of_random_graphs_against_reference(self):
        set_random_seed(0)
        for n in range(9, 13):
            for density in [0.2, 0.5, 0.8]:
                for _ in range(10):
                    graph = graphs.RandomGNP(n, density)
                    proper_thinness = reference_proper_thinness(graph)
                    with self.subTest(graph=graph.graph6_string()):
                        self._assert_proper_thinness_of_graph(graph, proper_thinness)
                        self.assertEqual(
                            calculate_proper_thinness(graph, max_seen_entries=0),
                            proper_thinness,
                        )

    def test_proper_thinness_of_random_graphs_with_bitsets_against_reference(self):
        # Graphs this small are searched with 64-bit words, so force the search with bitsets.
        set_random_seed(0)
        with unittest.mock.patch.object(branch_and_bound, 'MAX_VERTICES_FOR_WORDS', 0):
            for n in range(9, 12):
                for density in [0.2, 0.5, 0.8]:
                    for _ in range(5):
                        graph = graphs.RandomGNP(n, density)
                        proper_thinness = reference_proper_thinness(graph)
                        with self.subTest(graph=graph.graph6_string()):
                            self._assert_proper_thinness_of_graph(graph, proper_thinness)


def reference_proper_thinness(graph: Graph) -> int:
    """Proper thinness computed by a plain search without any of the pruning rules of the branch and bound.

    Builds the order vertex by vertex, trying every vertex of the suffix on every
    part it can be added to. Only remembers the states already searched, where a
    state is the suffix and, for each part, its suffix neighbors and the suffix
    vertices that are forbidden from it.
    """
    graph = graph.relabel(inplace=False)
    n = graph.order()
    neighbors = [sum(1 << neighbor for neighbor in graph.neighbor_iterator(vertex)) for vertex in range(n)]
    for max_parts in itertools.count(1):
        if _has_proper_solution(n, neighbors, max_parts):
            return max_parts


def _has_proper_solution(n: int, neighbors: list[int], max_parts: int) -> bool:
    all_vertices = (1 << n) - 1
    seen_states = set()

    def extend(suffix: int, parts: tuple[tuple[int, int], ...]) -> bool:
        """Each part is its suffix neighbors and the suffix vertices that are forbidden from it."""
        if suffix == 0:
            return True
        if (suffix, parts) in seen_states:
            return False
        seen_states.add((suffix, parts))
        prefix = all_vertices & ~suffix
        for vertex in range(n):
            if not suffix >> vertex & 1:
                continue
            new_suffix = suffix & ~(1 << vertex)
            vertex_neighbors = neighbors[vertex] & new_suffix
            # A suffix vertex adjacent to a prefix non neighbor of `vertex` can't go after it in its part.
            newly_forbidden = 0
            for prefix_vertex in range(n):
                if prefix >> prefix_vertex & 1 and not neighbors[vertex] >> prefix_vertex & 1:
                    newly_forbidden |= neighbors[prefix_vertex]
            newly_forbidden &= new_suffix
            new_parts = [
                (part_neighbors & new_suffix, forbidden & new_suffix)
                for part_neighbors, forbidden in parts
            ]
            for part in range(len(parts) + 1):
                if part == len(parts):
                    if part == max_parts:
                        continue
                    next_parts = new_parts + [(vertex_neighbors, newly_forbidden)]
                else:
                    part_neighbors, forbidden = new_parts[part]
                    if parts[part][1] >> vertex & 1 or part_neighbors & ~vertex_neighbors:
                        continue
                    next_parts = list(new_parts)
                    next_parts[part] = (vertex_neighbors, forbidden | newly_forbidden)
                if extend(new_suffix, tuple(sorted(next_parts))):
                    return True
        return False

    return extend(all_vertices, ())

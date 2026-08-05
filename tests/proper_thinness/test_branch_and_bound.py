import unittest

from sage.graphs.graph import Graph
from sage.graphs.graph_generators import graphs
from sage.misc.randstate import set_random_seed

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

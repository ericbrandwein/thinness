import unittest

from sage.graphs.graph import Graph
from sage.graphs.graph_generators import graphs
from sage.misc.randstate import set_random_seed

from thinness.branch_and_bound import calculate_thinness_with_branch_and_bound
from thinness.z3 import Z3ThinnessSolver
from thinness.verify import verify_solution


class TestBranchAndBound(unittest.TestCase):
    def _assert_thinness_of_graph(self, graph: Graph, expected_thinness: int):
        actual_thinness = calculate_thinness_with_branch_and_bound(graph)
        self.assertEqual(actual_thinness, expected_thinness)
        solution = calculate_thinness_with_branch_and_bound(graph, certificate=True)
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
        calculate_thinness_with_branch_and_bound(graph)

    def test_thinness_of_random_graphs(self):
        set_random_seed(0)
        n = 8
        solver = Z3ThinnessSolver(n)
        for _ in range(100):
            graph = graphs.RandomGNP(n, 0.5)
            thinness = solver.solve(graph).thinness
            with self.subTest(graph=graph.graph6_string()):
                self._assert_thinness_of_graph(graph, thinness)
            
import unittest
from sage.graphs.graph_generators import graphs
from thinness import verify_solution

from z3_thinness import Z3ThinnessSolver


class TestZ3Thinness(unittest.TestCase):
    def test_thinness_of_complete_graph(self):
        graph = graphs.CompleteGraph(5)
        solution = Z3ThinnessSolver(5).solve(graph)
        self.assertEqual(solution.thinness, 1)
        self.assertTrue(verify_solution(graph, solution))
        
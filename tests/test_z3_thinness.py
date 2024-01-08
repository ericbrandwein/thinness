import unittest

from sage.graphs.graph_generators import graphs
from sage.graphs.graph import Graph


import pyximport; pyximport.install()
from thinness import verify_solution
from thinness.z3 import Z3ThinnessSolver


class TestZ3Thinness(unittest.TestCase):
    def test_thinness_of_complete_graph(self):
        graph = graphs.CompleteGraph(5)
        solution = Z3ThinnessSolver(5).solve(graph)
        self.assertEqual(solution.thinness, 1)
        self.assertTrue(verify_solution(graph, solution))

    def test_thinness_of_GVBOuO_with_order(self):
        graph = Graph('GVBOuO')
        order = graph.vertices()
        solution = Z3ThinnessSolver(graph.order()).solve(graph, partial_orders=[order])
        self.assertEqual(solution.order, order)
        self.assertTrue(verify_solution(graph, solution))
        
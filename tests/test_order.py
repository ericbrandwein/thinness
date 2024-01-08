import unittest

from sage.graphs.graph import Graph
from sage.graphs.graph_generators import graphs
from sage.misc.randstate import set_random_seed

from thinness.order import thinness_of_order
import pyximport; pyximport.install()
from thinness.z3 import Z3ThinnessSolver


class TestThinnessOfOrder(unittest.TestCase):
    def test_K1(self):
        graph = Graph(1)
        order = [0]
        self.assertEqual(thinness_of_order(graph, order), 1)

    def test_K2(self):
        graph = graphs.CompleteGraph(2)
        order = [0, 1]
        self.assertEqual(thinness_of_order(graph, order), 1)

    def test_K3(self):
        graph = graphs.CompleteGraph(3)
        order = [0, 1, 2]
        self.assertEqual(thinness_of_order(graph, order), 1)

    def test_C4(self):
        graph = graphs.CycleGraph(4)
        order = [0, 1, 2, 3]
        self.assertEqual(thinness_of_order(graph, order), 2)

    def test_many_graphs(self):
        set_random_seed(0)
        n = 8
        solver = Z3ThinnessSolver(n)
        for _ in range(100):
            graph = graphs.RandomGNP(n, 0.5)
            with self.subTest(graph=graph.graph6_string()):
                order = graph.vertices()
                expected_thinness = solver.solve(graph, partial_orders=[order]).thinness
                self.assertEqual(thinness_of_order(graph, order), expected_thinness)

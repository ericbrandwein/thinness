import unittest

from sage.graphs.graph import Graph
from sage.graphs.graph_generators import graphs

from thinness.reduce import reduce_graph
import pyximport; pyximport.install()
from thinness.z3 import Z3ThinnessSolver


class TestReduce(unittest.TestCase):
    def test_reduce_K1(self):
        graph = graphs.CompleteGraph(1)
        reduced_graph, reduced_thinness = reduce_graph(graph)
        self.assertEqual(reduced_graph, graph)
        self.assertEqual(reduced_thinness, 0)

    def test_reduce_K2(self):
        graph = graphs.CompleteGraph(2)
        reduced_graph, reduced_thinness = reduce_graph(graph)
        self.assertEqual(reduced_graph, graphs.CompleteGraph(1))
        self.assertEqual(reduced_thinness, 0)

    def test_reduce_3_independent_vertices(self):
        graph = Graph(3)
        reduced_graph, reduced_thinness = reduce_graph(graph)
        self.assertEqual(reduced_graph, Graph(2))
        self.assertEqual(reduced_thinness, 0)

    def test_reduce_C4(self):
        graph = graphs.CycleGraph(4)
        reduced_graph, reduced_thinness = reduce_graph(graph)
        self.assertEqual(reduced_graph, Graph(2))
        self.assertEqual(reduced_thinness, 1)

    def test_maintains_thinness(self):
        n = 8
        solver = Z3ThinnessSolver(n)
        for _ in range(100):
            graph = graphs.RandomGNP(n, 0.5)
            with self.subTest(graph=graph.graph6_string()):
                reduced_graph, reduced_thinness = reduce_graph(graph)
                reduced_solver = Z3ThinnessSolver(reduced_graph.order())
                self.assertEqual(solver.solve(graph).thinness, reduced_solver.solve(reduced_graph).thinness + reduced_thinness)

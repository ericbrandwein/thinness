import unittest

from sage.graphs.graph import Graph
from sage.graphs.graph_generators import graphs
from sage.misc.randstate import set_random_seed
from sage.graphs.graph_decompositions.vertex_separation import vertex_separation

from thinness.verify import verify_solution
from thinness.vertex_separation import solution_from_vertex_separation


class TestVertexSeparation(unittest.TestCase):
    def test_trivial_graph(self):
        graph = Graph(1)
        linear_layout = [0]
        vertex_separation = 0

        solution = solution_from_vertex_separation(graph, linear_layout, vertex_separation)

        self.assertEqual(solution.thinness, 1)
        self.assertTrue(verify_solution(graph, solution))

    def test_K2(self):
        n = 2
        graph = graphs.CompleteGraph(n)
        linear_layout = [0, 1]
        vertex_separation = 1

        solution = solution_from_vertex_separation(graph, linear_layout, vertex_separation)

        self.assertEqual(solution.thinness, vertex_separation)
        self.assertTrue(verify_solution(graph, solution))

    def test_K3(self):
        n = 3
        graph = graphs.CompleteGraph(n)
        linear_layout = [0, 1, 2]
        vertex_separation = 2

        solution = solution_from_vertex_separation(graph, linear_layout, vertex_separation)

        self.assertEqual(solution.thinness, vertex_separation)
        self.assertTrue(verify_solution(graph, solution))

    def test_inactive_vertices(self):
        graph = Graph({
            0: [1,2],
            1: [],
            2: [],
        })
        linear_layout = [0, 1, 2]
        vertex_separation = 1

        solution = solution_from_vertex_separation(graph, linear_layout, vertex_separation)

        self.assertEqual(solution.thinness, vertex_separation)
        self.assertTrue(verify_solution(graph, solution))

    @unittest.skip("vertex_separation() is broken, doesn't matter which algorithm you use.")
    def test_many_graphs(self):
        set_random_seed(0)
        for _ in range(100):
            graph = graphs.RandomGNP(5, 0.5)
            cost, layout = vertex_separation(graph)
            with self.subTest(graph=graph.graph6_string()):
                solution = solution_from_vertex_separation(graph, layout, cost)
                thinness = max(1, cost)
                self.assertEqual(solution.thinness, thinness, f"Solution: {solution}, linear layout: {layout}, cost: {cost}")
                self.assertTrue(verify_solution(graph, solution))
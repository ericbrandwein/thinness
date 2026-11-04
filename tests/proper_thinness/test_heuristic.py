import unittest

from sage.graphs.graph_generators import graphs
from sage.misc.randstate import set_random_seed

from proper_thinness.heuristic import heuristic_solution
from proper_thinness.verify import verify_solution
from tests.proper_thinness.test_branch_and_bound import reference_proper_thinness
from thinness.time_branch_and_bound import crown_graph, cylinder_graph


class TestHeuristic(unittest.TestCase):
    def test_solutions_of_random_graphs(self):
        set_random_seed(0)
        for n in range(1, 13):
            for density in [0.2, 0.5, 0.8]:
                for _ in range(5):
                    graph = graphs.RandomGNP(n, density)
                    solution = heuristic_solution(graph)
                    with self.subTest(graph=graph.graph6_string()):
                        self.assertTrue(verify_solution(graph, solution))
                        self.assertGreaterEqual(solution.thinness, reference_proper_thinness(graph))

    def test_solutions_of_larger_graphs_are_valid(self):
        for name, graph in [
            ('crown 8', crown_graph(8)),
            ('grid 6x6', graphs.Grid2dGraph(6, 6)),
            ('cylinder 4x7', cylinder_graph(4, 7)),
            ('co-10K2', (graphs.CompleteGraph(2) * 10).complement()),
        ]:
            with self.subTest(graph=name):
                self.assertTrue(verify_solution(graph, heuristic_solution(graph)))

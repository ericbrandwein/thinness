import unittest
from sage import all
from sage.graphs.graph_generators import graphs
from proper_thinness.verify import verify_solution
from thinness.consistent_solution import ConsistentSolution
import pyximport; pyximport.install()
from thinness.z3 import Z3ProperThinnessSolver


class TestVerify(unittest.TestCase):
    def test_verify_solution_with_bad_partition(self):
        graph = graphs.CompleteGraph(1)
        solution = ConsistentSolution([0], [])
        self.assertFalse(verify_solution(graph, solution))

    def test_verify_solution_with_valid_solution(self):
        graph = graphs.CompleteGraph(1)
        solution = ConsistentSolution([0], [{0}])
        self.assertTrue(verify_solution(graph, solution))

    def test_verify_solution_with_graphs_up_to_6_vertices(self):
        for graph in graphs(6):
            solution = Z3ProperThinnessSolver(graph.order()).solve(graph)
            self.assertTrue(verify_solution(graph, solution))

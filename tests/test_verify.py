import unittest
from sage import all
from sage.graphs.graph import Graph
from sage.graphs.graph_generators import graphs
from thinness.verify import verify_solution
from thinness.consistent_solution import ConsistentSolution
from thinness.branch_and_bound import calculate_thinness


class TestVerify(unittest.TestCase):
    def test_verify_solution_with_bad_partition(self):
        graph = graphs.CompleteGraph(1)
        solution = ConsistentSolution([0], [])
        self.assertFalse(verify_solution(graph, solution))

    def test_verify_solution_with_valid_solution(self):
        graph = graphs.CompleteGraph(1)
        solution = ConsistentSolution([0], [{0}])
        self.assertTrue(verify_solution(graph, solution))

    def test_verify_solution_with_vertices_of_same_class_not_consecutive_in_order(self):
        # 0 < 2 < 3 with 0 and 2 in the same class, 03 is an edge and 23 is not.
        graph = Graph([(0, 3)])
        graph.add_vertices([1, 2])
        solution = ConsistentSolution([0, 1, 2, 3], [{0, 2}, {1, 3}])
        self.assertFalse(verify_solution(graph, solution))

    def test_verify_solution_with_graphs_up_to_7_vertices(self):
        for graph in graphs(7):
            solution = calculate_thinness(graph, certificate=True)
            self.assertTrue(verify_solution(graph, solution))

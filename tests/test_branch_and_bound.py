import unittest
import itertools

from sage.graphs.graph import Graph
from sage.graphs.graph_generators import graphs
from sage.misc.randstate import set_random_seed

from thinness.branch_and_bound import calculate_thinness
from thinness.z3 import Z3ThinnessSolver
from thinness.verify import verify_solution
from thinness.shower import show_graph, show_solution

class TestBranchAndBound(unittest.TestCase):
    def _assert_thinness_of_graph(self, graph: Graph, expected_thinness: int):
        actual_thinness = calculate_thinness(graph)
        self.assertEqual(actual_thinness, expected_thinness)
        solution = calculate_thinness(graph, certificate=True)
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
        calculate_thinness(graph)

    def test_crown_graphs(self):
        for n in range(2, 10):
            graph = crown_graph(n)
            thinness = n - 1
            with self.subTest(graph=graph.graph6_string()):
                self._assert_thinness_of_graph(graph, thinness)

    def test_complement_of_nK2(self):
        for n in range(1, 10):
            graph = (graphs.CompleteGraph(2) * n).complement()
            thinness = n
            with self.subTest(graph=graph.graph6_string()):
                self._assert_thinness_of_graph(graph, thinness)

    def test_thinness_of_random_graphs(self):
        set_random_seed(0)
        n = 8
        solver = Z3ThinnessSolver(n)
        for _ in range(100):
            graph = graphs.RandomGNP(n, 0.5)
            thinness = solver.solve(graph).thinness
            with self.subTest(graph=graph.graph6_string()):
                self._assert_thinness_of_graph(graph, thinness)

    def test_thinness_of_join(self):
        graph = Graph('GCOf?w')
        self._assert_thinness_of_graph(graph, 2)
        joined_graph = graph.join(Graph(1), labels='integers')
        self._assert_thinness_of_graph(joined_graph, 2)

    def test_thinness_of_induced_subgraphs(self):
        first = Graph(r'Mi\rzx?OA@gEONON?')
        second = Graph(r'Si\rzx?OA@gEONONG?A??O?L??q?@y?@w')
        self.assertTrue(first.is_subgraph(second, induced=True, up_to_isomorphism=True))
        self.assertGreaterEqual(calculate_thinness(second), calculate_thinness(first))


def crown_graph(vertices_per_side: int) -> Graph:
    graph = Graph(2*vertices_per_side)
    for u, v in itertools.permutations(range(vertices_per_side), 2):
        graph.add_edge(u, v + vertices_per_side)
    return graph
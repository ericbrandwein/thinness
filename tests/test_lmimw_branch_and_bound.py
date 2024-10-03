import unittest
import itertools

from sage.graphs.graph import Graph
from sage.graphs.graph_generators import graphs
from sage.misc.randstate import set_random_seed

from lmimw.branch_and_bound import lmimwidth


class TestLmimwBranchAndBound(unittest.TestCase):

    def test_lmimw_of_independent_graphs(self):
        for i in range(1, 21):
            graph = Graph(i)
            with self.subTest(i=i):
                self.assertEqual(lmimwidth(graph), 0)

    def test_lmimw_of_path_graphs(self):
        for i in range(2, 5):
            graph = graphs.PathGraph(i)
            with self.subTest(i=i):
                self.assertEqual(lmimwidth(graph), 1)

    def test_lmimw_of_complete_graphs(self):
        for i in range(2, 5):
            graph = graphs.CompleteGraph(i)
            with self.subTest(i=i):
                self.assertEqual(lmimwidth(graph), 1)
    
    def test_lmimw_of_cycle_4(self):
        graph = graphs.CycleGraph(4)
        lmimw, order = lmimwidth(graph, certificate=True)
        self.assertEqual(lmimw, 1)
        self.assertEqual(order, [0, 2, 1, 3])

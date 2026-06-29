import unittest
from math import floor, ceil
from sage.graphs.graph import Graph
from thinness import ConsistentSolution, verify_solution
from thinness.thick_spider import *


class TestBuildSpider2Graph(unittest.TestCase):
    def test_with_five_vertices_in_each_side(self):
        graph: Graph = build_thick_spider_graph(vertices_per_side=5)
        
        vertices_complete = range(5)
        vertices_independent = range(5, 10)
        self.assertEqual(graph.order(), 10)
        self.assertTrue(graph.is_clique(vertices_complete))
        self.assertTrue(graph.is_independent_set(vertices_independent))
        for i, j in zip(vertices_complete, vertices_independent):
            self.assertFalse(graph.has_edge(i,j))
        for index_i, i in enumerate(vertices_complete):
            for index_j, j in enumerate(vertices_independent):
                if index_i != index_j:
                    with self.subTest(i=i, j=j):
                        self.assertTrue(graph.has_edge(i,j)) 


class TestThinnessOfSplitCrownGraph(unittest.TestCase):
    def test(self):
        for vertices_per_side in range(3, 20):
            with self.subTest(vertices_per_side=vertices_per_side):
                solution: ConsistentSolution = thinness_of_thick_spider_graph(vertices_per_side)
                expected = set(range(0,vertices_per_side*2))
                self.assertTrue(set(solution.order),expected)
                partition_union = set().union(*solution.partition)
                self.assertTrue(partition_union,expected)
                
                self.assertEqual(solution.thinness, ceil(vertices_per_side / 2))
                self.assertTrue(verify_solution(build_thick_spider_graph(vertices_per_side), solution))
    
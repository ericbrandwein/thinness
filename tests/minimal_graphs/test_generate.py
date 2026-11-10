import tempfile
import unittest
import unittest.mock

import numpy as np
from sage.graphs.graph import Graph
from sage.graphs.graph_generators import graphs

from minimal_graphs import generate
from minimal_graphs.classify import canonical_form_of_graph6
from thinness.branch_and_bound import calculate_thinness
from proper_thinness.branch_and_bound import calculate_proper_thinness
from proper_thinness.heuristic import solution_from_order

MAX_ORDER = 8
# The values of the larger orders take too long to check one by one.
MAX_ORDER_CHECKED_AGAINST_BRANCH_AND_BOUND = 7


class TestGenerate(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.directory = tempfile.TemporaryDirectory()
        # So that the larger orders are split in chunks too.
        with unittest.mock.patch.object(generate, 'MIN_ORDER_FOR_CHUNKS', 6):
            generate.generate(MAX_ORDER, cls.directory.name, processes=2, chunks=3)

    @classmethod
    def tearDownClass(cls):
        cls.directory.cleanup()

    def test_values_match_the_branch_and_bound(self):
        for order in range(1, MAX_ORDER_CHECKED_AGAINST_BRANCH_AND_BOUND + 1):
            table = np.fromfile(f'{self.directory.name}/order-{order}.table', dtype=np.uint64).reshape(-1, 2)
            values = {int(key) >> 8: int(key) & 0xff for key in table[:, 0]}
            connected_graphs = list(graphs.nauty_geng(f'-c {order}'))
            self.assertEqual(len(values), len(connected_graphs))
            for graph in connected_graphs:
                _, form = canonical_form_of_graph6(graph.graph6_string().encode())
                with self.subTest(graph=graph.graph6_string()):
                    self.assertEqual(values[form] >> 4, calculate_thinness(graph))
                    self.assertEqual(values[form] & 15, calculate_proper_thinness(graph))

    def test_orders_in_the_tables_are_optimal_for_the_proper_thinness(self):
        for order in range(1, MAX_ORDER + 1):
            table = np.fromfile(f'{self.directory.name}/order-{order}.table', dtype=np.uint64).reshape(-1, 2)
            for key, packed_order in table:
                key, packed_order = int(key), int(packed_order)
                # The canonically labelled graph, whose edges are the bits of the canonical form.
                pairs = [(i, j) for j in range(1, order) for i in range(j)]
                graph = Graph([list(range(order)), [pair for bit, pair in enumerate(pairs) if key >> (8 + bit) & 1]])
                vertex_order = [packed_order >> (4 * i) & 15 for i in range(order)]
                with self.subTest(graph=graph.graph6_string()):
                    self.assertEqual(sorted(vertex_order), list(range(order)))
                    self.assertEqual(solution_from_order(graph, vertex_order).thinness, key & 15)

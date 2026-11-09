import tempfile
import unittest
import unittest.mock

import numpy as np
from sage.graphs.graph_generators import graphs

from minimal_graphs import compare, generate
from minimal_graphs.classify import canonical_form_of_graph6
from thinness.branch_and_bound import calculate_thinness
from proper_thinness.branch_and_bound import calculate_proper_thinness

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
            table = np.fromfile(f'{self.directory.name}/order-{order}.table', dtype=np.uint64)
            values = {int(entry) >> 8: int(entry) & 0xff for entry in table}
            connected_graphs = list(graphs.nauty_geng(f'-c {order}'))
            self.assertEqual(len(values), len(connected_graphs))
            for graph in connected_graphs:
                _, form = canonical_form_of_graph6(graph.graph6_string().encode())
                with self.subTest(graph=graph.graph6_string()):
                    self.assertEqual(values[form] >> 4, calculate_thinness(graph))
                    self.assertEqual(values[form] & 15, calculate_proper_thinness(graph))

    def test_minimal_graphs_match_the_data(self):
        self.assertTrue(compare.compare(self.directory.name))

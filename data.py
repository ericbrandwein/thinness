import csv
import os
from sage.graphs.graph import Graph


DATA_DIR = 'data'
LAST_PROCESSED_INDEX_FILENAME = f'{DATA_DIR}/last-processed.index'
THINNESS = 'thinness'
PROPER_THINNESS = 'proper-thinness'
MAX_THINNESS = 5
MAX_ORDER = 10


def save_last_processed_index(index):
    with open(LAST_PROCESSED_INDEX_FILENAME, mode='w', newline='') as file:
        file.write(str(index))


def get_last_processed_index():
    if os.path.exists(LAST_PROCESSED_INDEX_FILENAME):
        with open(LAST_PROCESSED_INDEX_FILENAME, mode='r', newline='') as file:
            return int(file.read())
    return -1


def load_graphs_from_csv(filename):
    with open(filename, newline='') as csvfile:
        reader = csv.DictReader(csvfile)
        return [
            Graph(row['graph6'], immutable=True)
            for row in reader
        ]


def write_graph_to_csv(graph6, filename):
    with open(filename, mode='a', newline='') as csvfile:
        writer = csv.writer(csvfile)
        writer.writerow([graph6, '', ''])


def _width_parameter_graphs_filename(width_parameter, value):
    return f'{DATA_DIR}/{width_parameter}-{value}.csv'


def _save_graph_with_width_parameter(graph6, width_parameter, value):
    write_graph_to_csv(graph6, _width_parameter_graphs_filename(width_parameter, value))


def save_graph_with_thinness(graph6, thinness):
    _save_graph_with_width_parameter(graph6, THINNESS, thinness)


def save_graph_with_proper_thinness(graph6, proper_thinness):
    _save_graph_with_width_parameter(graph6, PROPER_THINNESS, proper_thinness)


def _load_graphs_with_width(width_parameter, value):
    return load_graphs_from_csv(_width_parameter_graphs_filename(width_parameter, value))


def _load_graphs_by_width_parameter(n, width_parameter):
    input_dict = {}
    for k in range(2, MAX_THINNESS + 1):
        input_dict[k] = _load_graphs_with_width(width_parameter, k)
    output_dict = {}
    for k in range(2, MAX_THINNESS + 1):
        output_dict[k] = [graph for graph in input_dict[k] if graph.order() <= n]
    return output_dict


def load_graphs_by_thinness(n=MAX_ORDER):
    r""" Outputs the same as `graphs_by_thinness` by using precomputed values.

    TESTS::

        sage: Counter([G.canonical_label() for G in graphs_by_thinness_precomputed(6)[2]]) == Counter([G.canonical_label() for G in graphs_by_thinness(6)[2]])
        True
        sage: Counter([G.canonical_label() for G in graphs_by_thinness_precomputed(6)[3]]) == Counter([G.canonical_label() for G in graphs_by_thinness(6)[3]])
        True
        sage: len([G for G in graphs_by_thinness_precomputed(6, minimal_only=False)[1] if len(G.vertices()) == 6])
        56
    """
    return _load_graphs_by_width_parameter(n, THINNESS)


def load_graphs_by_proper_thinness(n=MAX_ORDER):
    r""" Outputs the same as `graphs_by_proper_thinness` by using precomputed values.

    TESTS::

        sage: Counter([G.canonical_label() for G in graphs_by_proper_thinness_precomputed(6)[2]]) == Counter([G.canonical_label() for G in graphs_by_proper_thinness(6)[2]])
        True
        sage: Counter([G.canonical_label() for G in graphs_by_proper_thinness_precomputed(6)[3]]) == Counter([G.canonical_label() for G in graphs_by_proper_thinness(6)[3]])
        True
        sage: len([G for G in graphs_by_proper_thinness_precomputed(6, minimal_only=False)[1] if len(G.vertices()) == 6])
        26
    """
    return _load_graphs_by_width_parameter(n, PROPER_THINNESS)
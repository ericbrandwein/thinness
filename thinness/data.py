import csv
import glob
import lzma
import os
import re
from sage.graphs.graph import Graph


# Where `minimal_graphs.generate` writes the lists of minimal graphs. The lists
# published in Zenodo can be put here too, compressed or not.
DATA_DIR = 'data/generated'
THINNESS = 'thinness'
PROPER_THINNESS = 'proper-thinness'
# Larger orders have millions of minimal graphs.
MAX_ORDER = 10


def load_graphs_from_csv(filename, n=None):
    """The graphs of a list of minimal graphs, `.csv` or `.csv.xz`, with up to `n` vertices if given."""
    open_file = lzma.open if filename.endswith('.xz') else open
    with open_file(filename, mode='rt', newline='') as csvfile:
        reader = csv.DictReader(csvfile)
        return [
            Graph(row['graph6'], immutable=True)
            for row in reader
            if n is None or _graph6_order(row['graph6']) <= n
        ]


def _graph6_order(graph6):
    # The first character is the order plus 63, for orders up to 62.
    return ord(graph6[0]) - 63


def _load_graphs_by_width_parameter(n, width_parameter, directory):
    """The minimal graphs with up to `n` vertices of each value of the parameter."""
    graphs_by_value = {}
    for filename in glob.glob(os.path.join(directory, f'{width_parameter}-*.csv*')):
        match = re.fullmatch(rf'{width_parameter}-(\d+)\.csv(\.xz)?', os.path.basename(filename))
        if match:
            graphs_by_value[int(match.group(1))] = load_graphs_from_csv(filename, n)
    if not graphs_by_value:
        raise FileNotFoundError(f'No lists of minimal graphs for {width_parameter} in {directory}')
    return dict(sorted(graphs_by_value.items()))


def load_graphs_by_thinness(n=MAX_ORDER, directory=DATA_DIR):
    r""" Outputs the same as `graphs_by_thinness` by using precomputed values.

    TESTS::

        sage: Counter([G.canonical_label() for G in graphs_by_thinness_precomputed(6)[2]]) == Counter([G.canonical_label() for G in graphs_by_thinness(6)[2]])
        True
        sage: Counter([G.canonical_label() for G in graphs_by_thinness_precomputed(6)[3]]) == Counter([G.canonical_label() for G in graphs_by_thinness(6)[3]])
        True
        sage: len([G for G in graphs_by_thinness_precomputed(6, minimal_only=False)[1] if len(G.vertices()) == 6])
        56
    """
    return _load_graphs_by_width_parameter(n, THINNESS, directory)


def load_graphs_by_proper_thinness(n=MAX_ORDER, directory=DATA_DIR):
    r""" Outputs the same as `graphs_by_proper_thinness` by using precomputed values.

    TESTS::

        sage: Counter([G.canonical_label() for G in graphs_by_proper_thinness_precomputed(6)[2]]) == Counter([G.canonical_label() for G in graphs_by_proper_thinness(6)[2]])
        True
        sage: Counter([G.canonical_label() for G in graphs_by_proper_thinness_precomputed(6)[3]]) == Counter([G.canonical_label() for G in graphs_by_proper_thinness(6)[3]])
        True
        sage: len([G for G in graphs_by_proper_thinness_precomputed(6, minimal_only=False)[1] if len(G.vertices()) == 6])
        26
    """
    return _load_graphs_by_width_parameter(n, PROPER_THINNESS, directory)


def read_adjacency_list_with_coordinates(filename):
    with open(filename) as file:
        lines = file.read().splitlines()
        graph = Graph(int(lines[0]))
        positions = {}
        for vertex, line in enumerate(lines[1:]):
            entries = line.split()
            positions[vertex] = entries[:2]
            neighbors = entries[2:]
            graph.add_edges((vertex, int(x)) for x in neighbors)

        graph.set_pos(positions)
    return graph


def write_adjacency_list_with_coordinates(graph: Graph, filename):
    relabeled = graph.relabel(inplace=False)
    with open(filename, 'w') as file:
        file.write(f'{relabeled.order()}\n')
        positions = relabeled.get_pos()
        for vertex in relabeled:
            neighbors = ' '.join(str(neighbor) for neighbor in relabeled.neighbors(vertex))
            file.write(f'{positions[vertex][0]} {positions[vertex][1]} {neighbors}\n')
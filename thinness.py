import csv
import os
from z3_thinness import calculate_thinness_with_z3
from helpers import *


def graphs_by_thinness(n, *, minimal_only=True):
    r""" Calculates the thinness of connected non-isomorphic graphs up to `n` vertices.

    TESTS::

        sage: {k: len(l) for k, l in graphs_by_thinness(4, minimal_only=False).items()}
        {1: 8, 2: 1}
        sage: {k: len(l) for k, l in graphs_by_thinness(5, minimal_only=False).items()}
        {1: 23, 2: 7}
        sage: {k: len(l) for k, l in graphs_by_thinness(6, minimal_only=False).items()}
        {1: 79, 2: 62, 3: 1}
        sage: {k: len(l) for k, l in graphs_by_thinness(4).items()}
        {1: 1, 2: 1}
        sage: {k: len(l) for k, l in graphs_by_thinness(5).items()}
        {1: 1, 2: 2}
        sage: {k: len(l) for k, l in graphs_by_thinness(6).items()}
        {1: 1, 2: 5, 3: 1}
        sage: [G for G in _connected_graphs_upto(6) if G.is_interval()] == graphs_by_thinness(6, minimal_only=False)[1]
        True
    """
    graphs_dict = {}
    for G in connected_graphs_upto(n):
        lower_bound = find_lower_bound(G, graphs_dict)
        k, _, _ = calculate_thinness_with_z3(G, lower_bound=lower_bound) 
        graphs_dict.setdefault(k, [])
        if minimal_only:
            if not has_induced_subgraph(G, graphs_dict[k]):
                graphs_dict[k].append(G)
        else:
            graphs_dict[k].append(G)
    return graphs_dict

def graphs_by_thinness_precomputed(n=8):
    r""" Outputs the same as `graphs_by_thinness` by using precomputed values.

    TESTS::

        sage: Counter([G.canonical_label() for G in graphs_by_thinness_precomputed(6)[2]]) == Counter([G.canonical_label() for G in graphs_by_thinness(6)[2]])
        True
        sage: Counter([G.canonical_label() for G in graphs_by_thinness_precomputed(6)[3]]) == Counter([G.canonical_label() for G in graphs_by_thinness(6)[3]])
        True
        sage: len([G for G in graphs_by_thinness_precomputed(6, minimal_only=False)[1] if len(G.vertices()) == 6])
        56
    """
    input_dict = {}
    for k in range(2, 5):
        input_dict[k] = load_graphs_from_csv(f'data/thinness-{k}.csv')
    output_dict = {}
    for k in range(2, 5):
        output_dict[k] = [graph for graph in input_dict[k] if graph.order() <= n]
    return output_dict


def write_graph_to_csv(G, filename):
    with open(filename, mode='a', newline='') as csvfile:
        writer = csv.writer(csvfile)
        writer.writerow([G.graph6_string(), G.name(), ''])


def save_graph_with_thinness(G, thinness):
    write_graph_to_csv(G, f'data/thinness-{thinness}.csv')


def save_last_processed_graph(G):
    with open('data/last-processed.graph6', mode='w', newline='') as file:
        file.write(G.graph6_string())


def get_last_processed_graph6():
    if os.path.exists('data/last-processed.graph6'):
        with open('data/last-processed.graph6', mode='r', newline='') as file:
            return file.read()
    return None


def process_graph(G, graphs_dict):
    lower_bound = find_lower_bound(G, graphs_dict)
    k, _, _ = calculate_thinness_with_z3(G, lower_bound=lower_bound) 
    if k > 1:
        graphs_dict.setdefault(k, [])
        if not has_induced_subgraph(G, graphs_dict[k]):
            save_graph_with_thinness(G, k)
            print('!!FOUND!!', G.graph6_string(), 'Thinness:', k, 'Vertices:', len(G.vertices()))
    save_last_processed_graph(G)


def fill_csvs():
    last_processed = get_last_processed_graph6()
    graphs_dict = graphs_by_thinness_precomputed()
    last_processed_found = last_processed is None
    for index, G in enumerate(connected_graphs_upto(9, start=9), start=1):
        if index % 1000 == 0:
            print('Graph number', index, 'reached')
        if not last_processed_found:
            graph6 = G.graph6_string()
            last_processed_found = graph6 == last_processed
            print('Not processing', graph6)
            continue
        process_graph(G, graphs_dict)


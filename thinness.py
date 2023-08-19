import csv
import os
import sys
import time
import multiprocessing as mp

from z3_thinness import calculate_thinness_with_z3
from helpers import *


GRAPHS_WITH_N_10 = 11716571
CHUNK_SIZE = 50
LAST_PROCESSED_FILENAME = 'data/last-processed.graph6'


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


def write_graph_to_csv(graph6, filename):
    with open(filename, mode='a', newline='') as csvfile:
        writer = csv.writer(csvfile)
        writer.writerow([graph6, '', ''])


def save_graph_with_thinness(graph6, thinness):
    write_graph_to_csv(graph6, f'data/thinness-{thinness}.csv')


def save_last_processed_graph(graph6):
    with open(LAST_PROCESSED_FILENAME, mode='w', newline='') as file:
        file.write(graph6)


def get_last_processed_graph6():
    if os.path.exists(LAST_PROCESSED_FILENAME):
        with open(LAST_PROCESSED_FILENAME, mode='r', newline='') as file:
            return file.read()
    return None


def process_graph(params):
    G, graphs_dict = params
    lower_bound = find_lower_bound(G, graphs_dict)
    k, _, _ = calculate_thinness_with_z3(G, lower_bound=lower_bound) 
    is_minimal = k > 1 and not has_induced_subgraph(G, graphs_dict[k])
    return G.graph6_string(), k, is_minimal


def print_updated_progress(index):
    if index % CHUNK_SIZE == 0:
        print(f'{index:,}/{GRAPHS_WITH_N_10:,} graphs processed, {GRAPHS_WITH_N_10 - index:,} remaining...', end='\r')


def print_found_graph(graph6, thinness):
    sys.stdout.write(u"\u001b[2K")
    print('Found minimal graph:', graph6, 'Thinness:', thinness)


def skip_graphs_until(graphs, graph6):
    for index, graph in enumerate(graphs, start = 1):
        if graph.graph6_string() == graph6:
            return index


def skip_processed_graphs(graphs):
    last_processed = get_last_processed_graph6()
    if last_processed:
        print('Skipping graphs until', last_processed)
        return skip_graphs_until(graphs, last_processed)
    else:
        return 0


def fill_csvs_paralelly(n=10):
    graphs_dict = graphs_by_thinness_precomputed(n=n-1)
    graphs_dict.setdefault(int(n/2), [])
    graphs = connected_graphs_upto(n, start=n)
    graphs_skipped = skip_processed_graphs(graphs)
        
    with mp.Pool() as pool:
        params = ((G, graphs_dict) for G in graphs)
        process_map = pool.imap(process_graph, params, chunksize=CHUNK_SIZE)
        for index, (graph6, thinness, is_minimal) in enumerate(process_map, start=graphs_skipped + 1):
            if is_minimal:
                save_graph_with_thinness(graph6, thinness)
                print_found_graph(graph6, thinness)
            save_last_processed_graph(graph6)
            print_updated_progress(index)
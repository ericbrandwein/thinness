import csv
import os
import sys
from datetime import datetime
import multiprocessing as mp

from z3_thinness import calculate_thinness_with_z3
from helpers import *


GRAPHS_WITH_N_10 = 11716571
CHUNK_SIZE = 50
LAST_PROCESSED_INDEX_FILENAME = 'data/last-processed.index'


def graphs_by_thinness_precomputed(n):
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


def save_last_processed_index(index):
    with open(LAST_PROCESSED_INDEX_FILENAME, mode='w', newline='') as file:
        file.write(str(index))


def get_last_processed_index():
    if os.path.exists(LAST_PROCESSED_INDEX_FILENAME):
        with open(LAST_PROCESSED_INDEX_FILENAME, mode='r', newline='') as file:
            return int(file.read())
    return -1


def process_graph(params):
    G, graphs_dict = params
    lower_bound = find_lower_bound(G, graphs_dict)
    k, _, _ = calculate_thinness_with_z3(G, lower_bound=lower_bound) 
    is_minimal = k > 1 and not has_induced_subgraph(G, graphs_dict[k])
    return G.graph6_string(), k, is_minimal


def estimate_time_remaining(start_time, graphs_processed, graphs_remaining):
    elapsed = datetime.today() - start_time
    time_per_graph = elapsed / graphs_processed
    return time_per_graph * graphs_remaining


def print_updated_progress(index, last_skipped_graph, start_time):
    if index % CHUNK_SIZE == 0:
        graphs_processed = index - last_skipped_graph
        graphs_remaining = GRAPHS_WITH_N_10 - index - 1
        time_remaining = estimate_time_remaining(start_time, graphs_processed, graphs_remaining)
        print(f'{index + 1:,} total graphs processed, {graphs_remaining:,} remaining. Time remaining: {time_remaining}', end='\r')


def print_found_graph(graph6, thinness):
    sys.stdout.write(u"\u001b[2K")
    print('Found minimal graph:', graph6, 'Thinness:', thinness)


def skip_graphs_until(graphs, index):
    for curr_index, _ in enumerate(graphs):
        if curr_index % 1000 == 0:
            print(f'Skipped {curr_index + 1:,}/{index + 1:,} graphs...', end='\r')
        if curr_index == index:
            print()
            break


def skip_processed_graphs(graphs):
    last_processed = get_last_processed_index()
    if last_processed > -1:
        print(f'Skipping first {last_processed + 1:,} graphs...')
        skip_graphs_until(graphs, last_processed)
    return last_processed


def fill_csvs_paralelly(n=10):
    graphs_dict = graphs_by_thinness_precomputed(n-1)
    graphs_dict.setdefault(int(n/2), [])
    graphs = connected_graphs_upto(n, start=n)
    last_skipped_graph = skip_processed_graphs(graphs)
    
    start_time = datetime.today()
    with mp.Pool() as pool:
        params = ((G, graphs_dict) for G in graphs)
        process_map = pool.imap(process_graph, params, chunksize=CHUNK_SIZE)
        for index, (graph6, thinness, is_minimal) in enumerate(process_map, start=last_skipped_graph + 1):
            if is_minimal:
                save_graph_with_thinness(graph6, thinness)
                print_found_graph(graph6, thinness)
            save_last_processed_index(index)
            print_updated_progress(index, last_skipped_graph, start_time)
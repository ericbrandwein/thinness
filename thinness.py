import sys
from datetime import datetime
import multiprocessing as mp

from z3_thinness import calculate_thinness_with_z3
from helpers import *
from data import load_graphs_by_thinness, save_graph_with_thinness, get_last_processed_index, save_last_processed_index


GRAPHS_WITH_N_10 = 11716571
CHUNK_SIZE = 50


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
    graphs_dict = load_graphs_by_thinness(n-1)
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
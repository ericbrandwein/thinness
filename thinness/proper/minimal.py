import sys
import itertools
from datetime import datetime
import multiprocessing as mp

from z3_thinness import calculate_proper_thinness_with_z3
from helpers import *
from data import load_graphs_by_proper_thinness, save_graph_with_proper_thinness, get_last_processed_index, save_last_processed_index


GRAPHS_OF_ORDER_10 = 11716571
GRAPHS_OF_ORDER_9 = 261080
CHUNK_SIZE = 50


def process_graph(params):
    G, graphs_dict = params
    lower_bound = find_lower_bound(G, graphs_dict)
    k, _, _ = calculate_proper_thinness_with_z3(G, lower_bound=lower_bound)
    is_minimal = k > 1 and not has_induced_subgraph(G, graphs_dict[k])
    return G.graph6_string(), k, is_minimal


def estimate_time_remaining(start_time, graphs_processed, graphs_remaining):
    elapsed = datetime.today() - start_time
    time_per_graph = elapsed / graphs_processed
    return time_per_graph * graphs_remaining


def print_updated_progress(index, last_skipped_graph, start_time):
    if index % CHUNK_SIZE == 0:
        graphs_processed = index - last_skipped_graph
        graphs_remaining = GRAPHS_OF_ORDER_10 - index - 1
        time_remaining = estimate_time_remaining(start_time, graphs_processed, graphs_remaining)
        print(f'{index + 1:,} total graphs processed, {graphs_remaining:,} remaining. Time remaining: {time_remaining}', end='\r', flush=True)


def print_found_graph(graph6, thinness):
    sys.stdout.write(u"\u001b[2K")
    print('Found minimal graph:', graph6, 'Proper thinness:', thinness)


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


def is_consistent_ordered_triple(graph, u, v, w, partition):
    return not graph.has_edge(u, w) or ((
        partition[u] != partition[v] or graph.has_edge(v, w)
    ) and (
        partition[v] != partition[w] or graph.has_edge(u, v)
    ))


def verify_solution(graph, order, partition):
    return all(
        is_consistent_ordered_triple(graph, u, v, w, partition)
        for u, v, w in itertools.combinations(order, 3)
    )


def fill_csvs_paralelly(n=9):
    graphs_dict = load_graphs_by_proper_thinness(n-1)
    for i in range(n):
        graphs_dict.setdefault(i, [])
    graphs = connected_graphs_upto(n, start=n)
    last_skipped_graph = skip_processed_graphs(graphs)
    
    start_time = datetime.today()
    with mp.Pool() as pool:
        params = ((G, graphs_dict) for G in graphs)
        process_map = pool.imap(process_graph, params, chunksize=CHUNK_SIZE)
        for index, (graph6, thinness, is_minimal) in enumerate(process_map, start=last_skipped_graph + 1):
            if is_minimal:
                save_graph_with_proper_thinness(graph6, thinness)
                print_found_graph(graph6, thinness)
            save_last_processed_index(index)
            print_updated_progress(index, last_skipped_graph, start_time)


def verify_graphs():
    graphs = load_graphs_by_proper_thinness(9)
    for graph in itertools.chain(*graphs.values()):
        _, order, partition = calculate_proper_thinness_with_z3(graph)
        assert verify_solution(graph, order, partition), f"Proper thinness for {graph.graph6_string()} was calculated incorrectly!!!!!"
    print("All graphs verified")
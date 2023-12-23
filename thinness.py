import sys
from datetime import datetime
import multiprocessing as mp

from z3_thinness import Z3ThinnessSolver
from helpers import *
from data import load_graphs_by_thinness, save_graph_with_thinness, get_last_processed_index, save_last_processed_index, save_all_graphs
from sage.graphs.trees import TreeIterator

TREES_FOR_EACH_ORDER = [1, 1, 1, 1, 2, 3, 6, 11, 23, 47, 106, 235, 551, 1301, 3159, 7741, 19320, 48629, 123867, 317955, 823065, 2144505, 5623756, 14828074, 39299897, 104636890, 279793450, 751065460, 2023443032, 5469566585, 14830871802, 40330829030, 109972410221, 300628862480, 823779631721, 2262366343746, 6226306037178] # https://oeis.org/A000055
GRAPHS_WITH_N_11 = 1006700565
GRAPHS_WITH_N_10 = 11716571
CHUNK_SIZE = 50


def init_process(number_of_vertices):
    global solver
    solver = Z3ThinnessSolver(number_of_vertices)


def process_graph(params):
    G = params
    solution = solver.solve(G)
    return G.graph6_string(), solution.thinness


def estimate_time_remaining(start_time, graphs_processed, graphs_remaining):
    elapsed = datetime.today() - start_time
    time_per_graph = elapsed / graphs_processed
    return time_per_graph * graphs_remaining


def print_updated_progress(index, last_skipped_graph, start_time, n):
    if index % CHUNK_SIZE == 0:
        graphs_processed = index - last_skipped_graph
        graphs_remaining = TREES_FOR_EACH_ORDER[n] - index - 1
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


def fill_csvs_paralelly(n=19):
    graphs = TreeIterator(n)
    last_skipped_graph = skip_processed_graphs(graphs)
    graphs_with_thinness = []

    try:
        start_time = datetime.today()
        with mp.Pool(initializer=init_process, initargs=(n,)) as pool:
            process_map = pool.imap(process_graph, graphs, chunksize=CHUNK_SIZE)
            for index, (graph6, thinness) in enumerate(process_map, start=last_skipped_graph + 1):
                graphs_with_thinness.append((graph6, n, thinness))
                print_updated_progress(index, last_skipped_graph, start_time, n)
    finally:
        print("Saving processed trees to data/all-trees.csv...")
        save_all_graphs(graphs_with_thinness, 'data/all-trees.csv')
        save_last_processed_index(index)
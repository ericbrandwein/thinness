import sys
from datetime import datetime
import multiprocessing as mp
from sage.graphs.graph import Graph

from z3_thinness import Z3ThinnessSolver
from helpers import *
from data import load_graphs_by_thinness, save_graph_with_thinness, get_last_processed_index, save_last_processed_index
from compatibility import build_compatibility_graph
from itertools_utils import skip_first

GRAPHS_WITH_N_10 = 11716571
CHUNK_SIZE = 50


def init_process(number_of_vertices):
    global solver
    solver = Z3ThinnessSolver(number_of_vertices)


def process_graph(params):
    G, graphs_dict = params
    solution = solver.solve(G)
    is_minimal = solution.thinness > 1 and not has_induced_subgraph(G, graphs_dict[solution.thinness])
    return G.graph6_string(), solution.thinness, is_minimal


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


def skip_processed_graphs(graphs):
    last_processed = get_last_processed_index()
    if last_processed > -1:
        print(f'Skipping first {last_processed + 1:,} graphs...', end='', flush=True)
        skip_first(graphs, last_processed + 1)
        print(" Done.")
    return last_processed


def fill_csvs_paralelly(n=10):
    graphs_dict = load_graphs_by_thinness(n-1)
    graphs_dict.setdefault(int(n/2), [])
    graphs = connected_graphs_upto(n, start=n)
    last_skipped_graph = skip_processed_graphs(graphs)
    
    start_time = datetime.today()
    with mp.Pool(initializer=init_process, initargs=(n,)) as pool:
        params = ((G, graphs_dict) for G in graphs)
        process_map = pool.imap(process_graph, params, chunksize=CHUNK_SIZE)
        for index, (graph6, thinness, is_minimal) in enumerate(process_map, start=last_skipped_graph + 1):
            if is_minimal:
                save_graph_with_thinness(graph6, thinness)
                print_found_graph(graph6, thinness)
            save_last_processed_index(index)
            print_updated_progress(index, last_skipped_graph, start_time)


def minimum_partition_for_vertex_order(graph: Graph, vertex_order: list[int]):
    compatibility_graph = build_compatibility_graph(graph, vertex_order)
    return compatibility_graph.coloring()


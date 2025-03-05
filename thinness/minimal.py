import sys
from tqdm import tqdm
from datetime import datetime
import multiprocessing as mp
from sage.graphs.graph import Graph

from .helpers import *
from .data import load_graphs_by_thinness, save_graph_with_thinness, get_last_processed_index, save_last_processed_index
from .compatibility import build_compatibility_graph
from .itertools_utils import skip_first
from .branch_and_bound import calculate_thinness


GRAPHS_PER_ORDER = [1,1,1,2,6,21,112,853,11117,261080,11716571,1006700565,164059830476,50335907869219,29003487462848061,31397381142761241960,63969560113225176176277,245871831682084026519528568,1787331725248899088890200576580,24636021429399867655322650759681644]
CHUNK_SIZE = 2000


def process_graph(params):
    G, graphs_dict = params
    thinness = calculate_thinness(G)
    is_minimal = thinness > 1 and not has_induced_subgraph(G, graphs_dict[thinness])
    return G.graph6_string(), thinness, is_minimal


# def estimate_time_remaining(start_time, graphs_processed, graphs_remaining):
#     elapsed = datetime.today() - start_time
#     time_per_graph = elapsed / graphs_processed
#     return time_per_graph * graphs_remaining


# def print_updated_progress(n, index, start_time):
#     if index % CHUNK_SIZE == 0:
#         graphs_processed = index + 1
#         graphs_remaining = GRAPHS_PER_ORDER[n] - graphs_processed
#         time_remaining = estimate_time_remaining(start_time, graphs_processed, graphs_remaining)
#         print(f'{graphs_processed:,} total graphs processed, {graphs_remaining:,} remaining. Time remaining: {time_remaining}', end='\r')


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
    # last_skipped_graph = skip_processed_graphs(graphs)
    
    with mp.Pool() as pool:
        params = ((G, graphs_dict) for G in graphs)
        process_map = pool.imap(process_graph, params, chunksize=CHUNK_SIZE)
        for graph6, thinness, is_minimal in tqdm(process_map):
            if is_minimal:
                save_graph_with_thinness(graph6, thinness)
                print_found_graph(graph6, thinness)


def minimum_partition_for_vertex_order(graph: Graph, vertex_order: list[int]):
    compatibility_graph = build_compatibility_graph(graph, vertex_order)
    return compatibility_graph.coloring()


if __name__ == '__main__':
    for i in range(4, 12):
        print(f'Processing graphs of order {i}...')
        fill_csvs_paralelly(i)
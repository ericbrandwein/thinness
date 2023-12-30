import itertools
import multiprocessing as mp

from helpers import load_graphs_from_csv, has_induced_subgraph
from z3_thinness import calculate_thinness_with_z3
from thinness import graphs_by_thinness_precomputed, verify_solution


def verify_csv_solutions(thinness):
    graphs = load_graphs_from_csv(f'data/thinness-{thinness}.csv')
    for index, G in enumerate(graphs):
        if index % 100 == 0:
            print(f'Thinnness {thinness} graph number {index} reached.')
        actual_thinness, order, partition = calculate_thinness_with_z3(G, upper_bound=thinness)
        if not verify_solution(G, partition, order) or actual_thinness != thinness:
            print(f'Thinnness {thinness} solutions INCORRECT: {G.graph6_string()}')
            return False
    print(f'Thinnness {thinness} solutions correct.')
    return True


def verify_all_csv_solutions():
    if all(mp.Pool().map(verify_csv_solutions, range(2, 5))):
        print('All solutions verified.')
    else:
        print('Some solutions are not correct.')


def verify_solutions_are_minimal(n=9, thinness=3):
    smaller_graphs = graphs_by_thinness_precomputed(n - 1)[thinness]
    graphs = [G for G in load_graphs_from_csv(f'data/thinness-{thinness}.csv') if G.order() == n]
    for index, G in enumerate(graphs):
        if index % 100 == 0:
            print(f'Thinnness {thinness} graph number {index} reached.')
        if has_induced_subgraph(G, smaller_graphs):
            print(f'Graph {G.graph6_string()} is not minimal!!!!!')
            return False
    return True    
    



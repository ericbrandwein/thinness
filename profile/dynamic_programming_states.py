"""Counts the states explored by the dynamic programming algorithm for thinness.

    PYTHONPATH=. python profile/dynamic_programming_states.py [--orders N ...] [--densities P ...] [--graphs G]

For each order and density, it runs it on G random graphs and prints the average
thinness, number of states and seconds, next to the bound of 3^n states.
"""
import argparse
import statistics
import time

from sage import all
from sage.graphs.graph_generators import graphs
from sage.misc.randstate import set_random_seed

from thinness.dynamic_programming import calculate_thinness_with_dynamic_programming


def count_states(orders, densities, graphs_per_case):
    set_random_seed(0)
    print('n\tp\tthinness\t3^n\tstates\tseconds')
    for n in orders:
        for p in densities:
            thinness_values = []
            states = []
            seconds = []
            for _ in range(graphs_per_case):
                graph = graphs.RandomGNP(n, p)
                start = time.perf_counter()
                thinness, explored = calculate_thinness_with_dynamic_programming(graph, count_states=True)
                seconds.append(time.perf_counter() - start)
                thinness_values.append(thinness)
                states.append(explored)
            print(
                f'{n}\t{p}\t{statistics.mean(thinness_values):.2f}\t{3 ** n}\t'
                f'{statistics.mean(states):.0f}\t{statistics.mean(seconds):.4f}',
                flush=True,
            )


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--orders', type=int, nargs='+', default=[8, 9, 10, 11, 12, 13, 14])
    parser.add_argument('--densities', type=float, nargs='+', default=[0.3, 0.5, 0.7])
    parser.add_argument('--graphs', type=int, default=10)
    arguments = parser.parse_args()
    count_states(arguments.orders, arguments.densities, arguments.graphs)

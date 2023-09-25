import csv
import os
from sage.graphs.graph import Graph


LAST_PROCESSED_INDEX_FILENAME = 'data/last-processed.index'


def load_graphs_from_csv(filename):
    with open(filename, newline='') as csvfile:
        reader = csv.DictReader(csvfile)
        return [
            Graph(row['graph6'], immutable=True)
            for row in reader
        ]


def write_graph_to_csv(graph6, filename):
    with open(filename, mode='a', newline='') as csvfile:
        writer = csv.writer(csvfile)
        writer.writerow([graph6, '', ''])


def save_graph_with_thinness(graph6, thinness):
    write_graph_to_csv(graph6, f'data/thinness-{thinness}.csv')


def save_graph_with_proper_thinness(graph6, proper_thinness):
    write_graph_to_csv(graph6, f'data/proper-thinness-{proper_thinness}.csv')


def save_last_processed_index(index):
    with open(LAST_PROCESSED_INDEX_FILENAME, mode='w', newline='') as file:
        file.write(str(index))


def get_last_processed_index():
    if os.path.exists(LAST_PROCESSED_INDEX_FILENAME):
        with open(LAST_PROCESSED_INDEX_FILENAME, mode='r', newline='') as file:
            return int(file.read())
    return -1
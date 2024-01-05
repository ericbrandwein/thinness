import itertools
from thinness import minimal, data, helpers, itertools_utils


def take(n, iterable):
    "Return first n items of the iterable as a list"
    return list(itertools.islice(iterable, n))


def profile():
    n = 10
    graphs_dict = data.load_graphs_by_thinness(n-1)
    graphs_dict.setdefault(int(n/2), [])
    graphs = helpers.connected_graphs_upto(n, start=n)

    print("Skipping graphs...")
    itertools_utils.skip_first(graphs, 1000)

    print("Processing graphs...")
    minimal.init_process(n)
    for graph in take(100, graphs):
        minimal.process_graph((graph, graphs_dict))


profile()

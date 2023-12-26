import cProfile
import itertools
import thinness
import data
import helpers


def take(n, iterable):
    "Return first n items of the iterable as a list"
    return list(itertools.islice(iterable, n))


def profile():
    n = 10
    graphs_dict = data.load_graphs_by_thinness(n-1)
    graphs_dict.setdefault(int(n/2), [])
    graphs = helpers.connected_graphs_upto(n, start=n)

    print("Skipping graphs...")
    thinness.skip_graphs_including(graphs, 1000)

    print("Processing graphs...")
    thinness.init_process(n)
    for graph in take(1000, graphs):
        thinness.process_graph((graph, graphs_dict))


cProfile.runctx("profile()", globals(), locals(), "profile.prof")

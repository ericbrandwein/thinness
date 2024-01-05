from sage.misc.randstate import set_random_seed
from sage.graphs.graph_generators import graphs


from thinness.branch_and_bound import calculate_thinness_with_branch_and_bound


def profile():
    set_random_seed(0)
    n = 10
    for _ in range(100):
        graph = graphs.RandomGNP(n, 0.5)
        calculate_thinness_with_branch_and_bound(graph)


profile()
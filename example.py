from sage import all
from sage.graphs.graph_generators import graphs
from thinness.branch_and_bound import calculate_thinness

for graph in graphs(8):
    print(graph.graph6_string(), calculate_thinness(graph))
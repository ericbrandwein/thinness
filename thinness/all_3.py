from thinness.data import load_graphs_by_thinness
from thinness.shower import show_graph_with_js
from lmimw.branch_and_bound import lmimwidth


graphs_by_thinness = load_graphs_by_thinness()
for graph in graphs_by_thinness[3]:
    print(graph.graph6_string())
    if lmimwidth(graph) < 3:
        show_graph_with_js(graph)
    input()

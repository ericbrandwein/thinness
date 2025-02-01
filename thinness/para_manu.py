from sage.graphs.graph_generators import graphs
from tqdm import tqdm

from thinness.data import load_graphs_by_thinness
from thinness.compatibility import build_compatibility_graph
from thinness.branch_and_bound import calculate_thinness


graphs_by_thinness = load_graphs_by_thinness()

for thinness, graphs in graphs_by_thinness.items():
    print('thinness:', thinness)
    for graph in tqdm(graphs):
        line_graph = graph.line_graph()
        thinness_of_line_graph = calculate_thinness(line_graph)
        if thinness_of_line_graph < thinness:
            print('Tomaaaaa manu')
            print('grafo:', graph.graph6_string(), 'thinness:', thinness)
            print('line graph:', line_graph.graph6_string(), 'thinness:', thinness_of_line_graph)
            exit()

print('Uh manu tenia razon')

# graph = graphs.PetersenGraph() # Elegir un grafo
# order = graph.vertices() # Elegir un orden
# compatibility_graph = build_compatibility_graph(graph)
# particion_optima = compatibility_graph.coloring()
# print(particion_optima)
        



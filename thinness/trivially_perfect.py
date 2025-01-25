from sage.graphs.graph_generators import graphs
from sage.graphs.graph import Graph
from thinness.z3 import Z3ProperThinnessSolver
import subprocess


def is_trivially_perfect(graph: Graph):
    """
    Checks if the given graph is trivially perfect.
    A graph is trivially perfect if it has no induced P4 or C4.
    """
    return not graphs.PathGraph(4).is_subgraph(graph, up_to_isomorphism=True) and not graphs.CycleGraph(4).is_subgraph(graph, up_to_isomorphism=True)


def show_graph(graph: Graph):
    file_path = 'trivially_perfect.png'
    graph.plot().save(file_path)
    subprocess.run(["xdg-open", file_path])


graph = (graphs.ClawGraph()*3).join(Graph(1), labels='integers')
show_graph(graph)
print(Z3ProperThinnessSolver(graph.order()).solve(graph))
# order = 10

# for graph in graphs(order):
#     if is_trivially_perfect(graph):
#         file_path = 'trivially_perfect.png'
#         graph.plot().save(file_path)
#         print(Z3ProperThinnessSolver(order).solve(graph))
#         subprocess.run(["xdg-open", file_path])
        
            

    



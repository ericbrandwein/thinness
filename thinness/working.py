from sage.all import *
from thinness.branch_and_bound import calculate_thinness
from thinness.shower import show_solution
from thinness.non_betweenness import non_betweenness
from itertools import combinations


# def calculate_and_show_thinness(filename='thinness/graph.g6'):
#     with open(filename, 'r') as file:
#         graph6_string = file.readline()
#         graph = Graph(graph6_string)

#     show_solution(graph, calculate_thinness(graph, certificate=True))

# calculate_and_show_thinness()

# number_of_elements = 5
# elements = list(range(number_of_elements))
# prohibitions = [
#     (i, (i + 3) % number_of_elements, (i + 1) % number_of_elements)
#     for i in elements
# ]
# print(prohibitions)

# print(non_betweenness(elements, prohibitions))


def chordal_graphs(n: int):
    return graphs.nauty_geng(f'-c -T {n}')


# for i in range(4, 100):
# for graph in chordal_graphs(11):
#     solution = calculate_thinness(graph, certificate=True)
#     if solution.thinness >= 3:
#         show_solution(graph, solution)
#         input()


def all_asteroidal_triples(graph):
    vertices = list(graph.vertices())
    for a, b, c in combinations(vertices, 3):
        if (not graph.has_edge(a, b) and not graph.has_edge(b, c) and not graph.has_edge(c, a)):
            without_a = graph.copy()
            without_a.delete_vertices(graph.neighbors(a, closed=True))
            without_b = graph.copy()
            without_b.delete_vertices(graph.neighbors(b, closed=True))
            without_c = graph.copy()
            without_c.delete_vertices(graph.neighbors(c, closed=True))
            if (a in without_b.connected_component_containing_vertex(c) and
                b in without_c.connected_component_containing_vertex(a) and
                c in without_a.connected_component_containing_vertex(b)):
                yield (a, b, c)

with open('thinness/possible-thin3.g6', 'r') as file:
    for line in file:
        g6 = line.strip()
        graph = Graph(g6)
        print(calculate_thinness(graph))
        show_solution(graph, calculate_thinness(graph, certificate=True))
# graph = Graph('J??FCtVJzv_')
# print(list(all_asteroidal_triples(graph)))
# show_solution(graph, calculate_thinness(graph, certificate=True))

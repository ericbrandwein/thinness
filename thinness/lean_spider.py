import itertools
from math import ceil
from sage.graphs.graph import Graph
from sage.graphs.graph_generators import graphs
from . import ConsistentSolution


def build_lean_spider_graph(vertices_per_side: int):
    """
    Los vertices del completo son del 0 al n-1
    Los vertices del independiente son del n al 2*n -1 
    """
    # Independent set (n isolated vertices)
    G1 = Graph(vertices_per_side)

    # Complete graph (n vertices)
    G2 = graphs.CompleteGraph(vertices_per_side)

    # Disjoint union
    G = G1.disjoint_union(G2,labels='integers')

    # Connect each independent node to a different complete node
    independent_nodes = list(range(vertices_per_side))      
    complete_nodes = list(range(vertices_per_side, 2*vertices_per_side))

    for u, v in zip(independent_nodes, complete_nodes):
        G.add_edge(u, v)
        G.add_edge((u+1)%vertices_per_side, v)
    Ls = G.complement()
    return Ls


def thinness_of_lean_spider_graph(vertices_per_side: int):
    return ConsistentSolution(_order(vertices_per_side), _partition(vertices_per_side))

def independent_node(index, vertices_per_side):
    return index+vertices_per_side
def complete_node(index, vertices_per_side):
    return index

def _order(vertices_per_side: int):
    order = [] # Agregar I_0,K_2,K_1
    order.append(independent_node(0,vertices_per_side))
    order.append(complete_node(2,vertices_per_side))
    order.append(complete_node(1,vertices_per_side))
    # Agregas las particiones de la forma I_i+2,I_i+1,I_i,K_i+4,K_i+3 donde i % 3 = 1
    for i in range(1,vertices_per_side-3,3):
        order.append(independent_node(i+2,vertices_per_side))
        order.append(independent_node(i+1,vertices_per_side))
        order.append(independent_node(i,vertices_per_side))
        order.append(complete_node((i+4)%vertices_per_side,vertices_per_side))
        order.append(complete_node((i+3)%vertices_per_side,vertices_per_side))
    if vertices_per_side % 3 == 2:
        order.append(independent_node(vertices_per_side-1,vertices_per_side))
    elif vertices_per_side % 3 == 0:
        order.append(independent_node(vertices_per_side-1,vertices_per_side))
        order.append(independent_node(vertices_per_side-2,vertices_per_side))
    else:
        order.append(independent_node(vertices_per_side-1,vertices_per_side))
        order.append(independent_node(vertices_per_side-2,vertices_per_side))
        order.append(independent_node(vertices_per_side-3,vertices_per_side))
    if vertices_per_side % 3 != 2:
        order.append(complete_node(0,vertices_per_side))
    for i in range(3,vertices_per_side,3):
        order.append(complete_node(i,vertices_per_side))
    return order


def _partition(vertices_per_side: int):
    partition = []
    part0 = []

    part0.append(independent_node(0,vertices_per_side))
    part0.append(complete_node(2,vertices_per_side))
    part0.append(complete_node(1,vertices_per_side))
    partition.append(part0)
    # Agregas las particiones de la forma I_i+2,I_i+1,I_i,K_i+4,K_i+3 donde i % 3 = 1
    for i in range(1,vertices_per_side-3,3):
        part_imod3 = [] 
        part_imod3.append(independent_node(i+2,vertices_per_side))
        part_imod3.append(independent_node(i+1,vertices_per_side))
        part_imod3.append(independent_node(i,vertices_per_side))
        part_imod3.append(complete_node((i+4)%vertices_per_side,vertices_per_side))
        part_imod3.append(complete_node((i+3)%vertices_per_side,vertices_per_side))
        partition.append(part_imod3)
    lastpart = []
    if vertices_per_side % 3 == 2:
        lastpart = partition[-1]
    else:
        partition.append(lastpart)
    
    if vertices_per_side % 3 == 2:
        lastpart.append(independent_node(vertices_per_side-1,vertices_per_side))
    elif vertices_per_side % 3 == 0:
        lastpart.append(independent_node(vertices_per_side-1,vertices_per_side))
        lastpart.append(independent_node(vertices_per_side-2,vertices_per_side))
    else:
        lastpart.append(independent_node(vertices_per_side-1,vertices_per_side))
        lastpart.append(independent_node(vertices_per_side-2,vertices_per_side))
        lastpart.append(independent_node(vertices_per_side-3,vertices_per_side))
    if vertices_per_side % 3 != 2:
        lastpart.append(complete_node(0,vertices_per_side))
    for i in range(3,vertices_per_side,3):
        lastpart.append(complete_node(i,vertices_per_side))
    return partition
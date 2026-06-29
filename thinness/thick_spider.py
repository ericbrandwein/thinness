import itertools
from math import ceil
from sage.graphs.graph import Graph
from sage.graphs.graph_generators import graphs
from . import ConsistentSolution


def build_thick_spider_graph(vertices_per_side: int):
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
    Ls = G.complement()
    return Ls


def thinness_of_thick_spider_graph(vertices_per_side: int):
    return ConsistentSolution(_order(vertices_per_side), _partition(vertices_per_side))

def independent_node(index, vertices_per_side):
    return index+vertices_per_side
def complete_node(index, vertices_per_side):
    return index

def _order(vertices_per_side: int):
    order = [] # Agregar I_0,K_1
    order.append(independent_node(0,vertices_per_side))
    order.append(complete_node(1,vertices_per_side)) # Habilita I2,I1,K3
    # Agregas las particiones de la forma I_i+1,I_i,K_i+2 donde i % 2 = 1
    for i in range(1,vertices_per_side-1,2):
        order.append(independent_node(i+1,vertices_per_side))
        order.append(independent_node(i,vertices_per_side))
        order.append(complete_node((i+2)%vertices_per_side,vertices_per_side))
    #Si n es 5, tenes los grupos {I_0,K_1},{I_2,I_1,K_3},{I_4,I_3,K_0} faltan {} faltan {K_2,K_4} 
    #Si n es 6, tenes los grupos {I_0,K_1},{I_2,I_1,K_3},{I_4,I_3,K_5}, faltan {I_5} faltan {K_0,K_2,K_4} 

    #Todos los restantes son vecinos entre si, podes agregarlos todos al ulitmo grupo
    if vertices_per_side % 2 == 0:
        order.append(independent_node(vertices_per_side-1,vertices_per_side))
        order.append(complete_node(0,vertices_per_side))
        
    #Si n es 5, tenes los grupos {I_0,K_1},{I_2,I_1,K_3},{I_4,I_3,K_0} faltan {} faltan {K_2,K_4} 
    #Si n es 6, tenes los grupos {I_0,K_1},{I_2,I_1,K_3},{I_4,I_3,K_5,I_5,K_0}, faltan {} faltan {K_2,K_4} 
    for i in range(2,vertices_per_side,2):
        order.append(complete_node(i,vertices_per_side))

    #Si n es 5, tenes los grupos {I_0,K_1},{I_2,I_1,K_3},{I_4,I_3,K_0,K_2,K_4}
    #Si n es 6, tenes los grupos {I_0,K_1},{I_2,I_1,K_3},{I_4,I_3,K_5,I_5,K_0,K_2,K_4}
    return order


def _partition(vertices_per_side: int):
    
    partition = []
    part0 = [] # Agregar I_0,K_1

    part0.append(independent_node(0,vertices_per_side))
    part0.append(complete_node(1,vertices_per_side)) # Habilita I2,I1,K3
    partition.append(part0)
    # Agregas las particiones de la forma I_i+1,I_i,K_i+2 donde i % 2 = 1
    for i in range(1,vertices_per_side-1,2):
        part_imod2 = [] 
        part_imod2.append(independent_node(i+1,vertices_per_side))
        part_imod2.append(independent_node(i,vertices_per_side))
        part_imod2.append(complete_node((i+2)%vertices_per_side,vertices_per_side))
        partition.append(part_imod2)
    #Si n es 5, tenes los grupos {I_0,K_1},{I_2,I_1,K_3},{I_4,I_3,K_0} faltan {} faltan {K_2,K_4} 
    #Si n es 6, tenes los grupos {I_0,K_1},{I_2,I_1,K_3},{I_4,I_3,K_5}, faltan {I_5} faltan {K_0,K_2,K_4} 
    #Todos los restantes son vecinos entre si, podes agregarlos todos al ulitmo grupo
    lastpart = partition[-1]

    if vertices_per_side % 2 == 0:
        lastpart.append(independent_node(vertices_per_side-1,vertices_per_side))
        lastpart.append(complete_node(0,vertices_per_side))
        
    #Si n es 5, tenes los grupos {I_0,K_1},{I_2,I_1,K_3},{I_4,I_3,K_0} faltan {} faltan {K_2,K_4} 
    #Si n es 6, tenes los grupos {I_0,K_1},{I_2,I_1,K_3},{I_4,I_3,K_5,I_5,K_0}, faltan {} faltan {K_2,K_4} 
    for i in range(2,vertices_per_side,2):
        lastpart.append(complete_node(i,vertices_per_side))

    return partition
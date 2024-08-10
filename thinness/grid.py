from sage.graphs.graph_generators import graphs
from thinness.branch_and_bound import calculate_thinness


def find_smallest_thin3_subgraph():
    rows = 4
    grid = graphs.Grid2dGraph(rows,rows)
    grid.relabel()
    subgraphs = []

    for row in range(rows):
        for col in range(rows):
            vertex = vertex_by_coordinates(row, col, rows)
            subgraph = grid.copy()
            subgraph.delete_vertex(vertex)
            thinness = calculate_thinness(subgraph, upper_bound=3)
            if thinness == 3:
                for row2 in range(rows):
                    for col2 in range(rows):
                        if row2 != row or col2 != col:
                            subgraph2 = subgraph.copy()
                            vertex = vertex_by_coordinates(row2, col2, rows)
                            subgraph2.delete_vertex(vertex)
                            thinness = calculate_thinness(subgraph2, upper_bound=3)
                            if thinness == 3:
                                subgraphs.append(subgraph2)

    print([subgraph.graph6_string() for subgraph in subgraphs])


def vertex_by_coordinates(row, col, rows):
    return row * rows + col


find_smallest_thin3_subgraph()
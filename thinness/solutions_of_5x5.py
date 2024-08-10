from sage.graphs.graph_generators import graphs

from thinness.branch_and_bound_all_solutions import calculate_thinness_of_connected_graph
from thinness.consistent_solution import ConsistentSolution
from thinness.itertools_utils import batched


def main():
    graph = graphs.Grid2dGraph(5, 5)
    graph.relabel()
    solutions = calculate_thinness_of_connected_graph(graph, upper_bound=3)
    for index, batch in enumerate(batched(solutions, 1000)):
        latex = to_latex(batch)
        with open(f'/tmp/grids_{index}.tex', 'w') as file:
            file.write(latex)


def to_latex(solutions: list[ConsistentSolution]):
    with open('templates/grids.tex', 'r') as grid_template:
        grid_template = grid_template.read()

    subfigures = ''
    with open('templates/grid-subfigure.tex', 'r') as subfigure_template:
        subfigure_template = subfigure_template.read()

    for triple in batched(solutions, 3):
        for solution in triple:
            subfigures += subfigure_template.replace('#vertices', to_latex_grid_vertices(solution))

    return grid_template.replace('#figures', subfigures)


def to_latex_grid_vertices(solution: ConsistentSolution):
    color_for_part=['brown', 'cyan', '']
    res = ''
    for vertex in range(len(solution.order)):
        res += f'{solution.order.index(vertex) + 1}/{color_for_part[solution.part_of(vertex)]}, '
    return res


def find_solution_without_same_class_row_or_column(solutions: list[ConsistentSolution], rows: int):
    for solution in solutions:
        if not row_shares_class(solution, rows) and not col_shares_class(solution, rows):
            return solution
    return None


def row_shares_class(solution: ConsistentSolution, rows: int):
    for row in range(rows):
        good_row = True
        first_vertex_in_row = vertex_by_coordinates(row, 0, rows)
        part = solution.part_of(first_vertex_in_row)
        for col in range(rows):
            vertex = vertex_by_coordinates(row, col, rows)
            if solution.part_of(vertex) != part:
                good_row = False
                break
        if good_row:
            return True
    return False


def col_shares_class(solution: ConsistentSolution, rows: int):
    for col in range(rows):
        good_col = True
        first_vertex_in_col = vertex_by_coordinates(0, col, rows)
        part = solution.part_of(first_vertex_in_col)
        for row in range(rows):
            vertex = vertex_by_coordinates(row, col, rows)
            if solution.part_of(vertex) != part:
                good_col = False
                break
        if good_col:
            return True
    return False


def vertex_by_coordinates(row: int, column: int, rows: int):
    return row * rows + column

main()


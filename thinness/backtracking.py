from dataclasses import dataclass
import itertools
import z3
from sage.graphs.graph import Graph

import pyximport; pyximport.install()
from .z3 import Z3ThinnessSolver


CONNECTED_GRAPHS_BY_ORDER = [1, 1, 1, 2, 6, 21, 112, 853, 11117, 261080, 11716571, 1006700565, 164059830476, 50335907869219, 29003487462848061, 31397381142761241960, 63969560113225176176277, 245871831682084026519528568, 1787331725248899088890200576580, 24636021429399867655322650759681644] # https://oeis.org/A001349

quantity_solved = 0

@dataclass(eq=True, frozen=True)
class SolvedGraph:
    canonical_label: str
    thinness: int

@dataclass
class SolvedGraphs:
    graphs: list[int, set[SolvedGraph]]

    def __init__(self, number_of_vertices):
        self.graphs = [set() for _ in range(number_of_vertices + 1)]

    def add(self, graph: SolvedGraph, number_of_vertices: int):
        self.graphs[number_of_vertices].add(graph)
    
    def contains(self, canonical_label: str, number_of_vertices: int):
        return canonical_label in self.graphs[number_of_vertices]


class ExtendableGraph:
    def __init__(self) -> None:
        self.graph = Graph()
        self._vertices_pushed = []

    def push_vertex(self, new_vertex, adjacency_list):
        self.graph.add_vertex(new_vertex)
        self.graph.add_edges((new_vertex, vertex) for vertex in adjacency_list)
        self._vertices_pushed.append(new_vertex)
    
    def pop_vertex(self):
        vertex = self._vertices_pushed.pop()
        self.graph.delete_vertex(vertex)

    def canonical_label(self):
        return self.graph.canonical_label().graph6_string()
    
    def order(self):
        return self.graph.order()
    
    def is_connected(self):
        return self.graph.is_connected()


class ExtendableZ3ThinnessSolver(Z3ThinnessSolver):
    def __init__(self, number_of_vertices):
        super().__init__(number_of_vertices)
        self._number_of_vertices_pushed = 0

    def solve(self, graph: Graph):
        self._add_missing_constraints(graph)
        if self.solver.check() == z3.sat:
            return self.solver.model()[self.variables.k_thin].as_long()

    def _add_missing_constraints(self, graph: Graph):
        total_number_of_vertices = graph.order()
        for vertex_missing in range(self._number_of_vertices_pushed, total_number_of_vertices):
            self._add_consistency_constraints_for_vertex(graph, vertex_missing)
        self._number_of_vertices_pushed = total_number_of_vertices

    def _add_consistency_constraints_for_vertex(self, graph: Graph, vertex: int):
        self.solver.push()
        for neighbor in filter(lambda other: other < vertex, graph.vertices()):
            if graph.has_edge(vertex, neighbor):
                self._add_consistency_constraints_for_neighbors(graph, vertex, neighbor)

    def _add_consistency_constraints_for_neighbors(self, graph, u, v):
        for non_neighbor in graph:
            if non_neighbor not in (u, v):
                if not graph.has_edge(v, non_neighbor):
                    self.solver.add(self.build_consistency_constraint(u, non_neighbor, v))
                if not graph.has_edge(u, non_neighbor):
                    self.solver.add(self.build_consistency_constraint(v, non_neighbor, u))
    
    def reduce_vertices(self, updated_vertices: int):
        for _ in range(updated_vertices, self._number_of_vertices_pushed):
            self.solver.pop()
            self._number_of_vertices_pushed -= 1
    

def solve_graphs(number_of_vertices):
    solver = ExtendableZ3ThinnessSolver(number_of_vertices)
    graph = ExtendableGraph()
    solved_graphs = SolvedGraphs(number_of_vertices)
    backtrack_graphs(solver, graph, number_of_vertices, solved_graphs)
    return solved_graphs.graphs[number_of_vertices]


def backtrack_graphs(
        solver: ExtendableZ3ThinnessSolver,
        graph: ExtendableGraph,
        number_of_vertices: int,
        solved_graphs: SolvedGraphs
):
    global quantity_solved
    if quantity_solved == 100:
        return
    canonical_label = graph.canonical_label()
    current_vertices = graph.order()
    if not solved_graphs.contains(canonical_label, current_vertices):
        thinness = None
        if current_vertices == number_of_vertices:
            thinness = process_graph(graph, solver)
        else:
            for adjacency_list in subsets(list(range(current_vertices))):
                new_vertex = current_vertices
                graph.push_vertex(new_vertex, adjacency_list)
                backtrack_graphs(solver, graph, number_of_vertices, solved_graphs)
                graph.pop_vertex()
                solver.reduce_vertices(current_vertices)
        solved_graphs.add(SolvedGraph(canonical_label, thinness), current_vertices)


def process_graph(graph: ExtendableGraph, solver: ExtendableZ3ThinnessSolver):
    global quantity_solved
    if graph.is_connected():
        print(f"Solved {quantity_solved} graphs.")
        quantity_solved += 1
        return solver.solve(graph.graph)


def subsets(list):
    for i in range(len(list) + 1):
        yield from itertools.combinations(list, i)
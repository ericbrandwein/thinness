from tempfile import NamedTemporaryFile
import subprocess


def show_graph_with_js(graph, **kwargs):
    graph.show(method='js', link_distance=0, charge=0, link_strength=0, gravity=0, force_spring_layout=False, **kwargs)


def show_plot(plot):
    with NamedTemporaryFile(suffix='.png', delete=False) as file:
        plot.save(file.name)
        print(file.name)
        subprocess.run(["xdg-open", file.name], check=True)


def show_graph(graph):
    show_plot(graph.plot())


def _partition_by_order(solution):
    return [
        {solution.order.index(v) for v in part}
        for part in solution.partition
    ]


def show_solution(graph, solution):
    graph.relabel({
        element: index
        for index, element in enumerate(solution.order)
    })
    show_plot(graph.plot(partition=_partition_by_order(solution)))
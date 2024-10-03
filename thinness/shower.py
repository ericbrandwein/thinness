def show_graph(graph, **kwargs):
    graph.show(method='js', link_distance=0, charge=0, link_strength=0, gravity=0, force_spring_layout=False, **kwargs)


def show_compatibility_graph(graph):
    show_graph(graph, edge_labels=True)


def _partition_by_order(solution):
    return [
        {solution.order.index(v) for v in part}
        for part in solution.partition
    ]


def plot_solution(graph, solution):
    graph.relabel({
        element: index
        for index, element in enumerate(solution.order)
    })
    graph.plot(partition=_partition_by_order(solution)).save('solution.png')
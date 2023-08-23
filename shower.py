def show_graph(graph, **kwargs):
    graph.show(method='js', link_distance=0, charge=0, link_strength=0, gravity=0, force_spring_layout=True, **kwargs)


def show_compatibility_graph(graph):
    show_graph(graph, edge_labels=True)
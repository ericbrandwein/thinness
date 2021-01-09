def rename(num):
    name = f't{num}'
    return lambda vertex: (name, vertex)

class Relabler:
    def __init__(self):
        self.curr_label = 0

    def __call__(self, vertex):
        if vertex == 'x':
            return 0
        else:
            self.curr_label += 1
            return self.curr_label

def next_level(graph):
    prev_graphs = [
        graph.relabel(perm=rename(i), inplace=False)
        for i in range(1,4)
    ]
    union = prev_graphs[0].union(prev_graphs[1].union(prev_graphs[2]))
    union.add_vertex('x')
    for i in range(1,4):
        union.add_edge('x', (f't{i}', 0))
    union.relabel(perm=Relabler())
    return union


three_claw_graph = next_level(graphs.ClawGraph())
nine_claw_graph = next_level(three_claw_graph)
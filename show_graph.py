import matplotlib.pyplot as plt
import networkx as nx
from graph_reader import read_graph
import sys


def show_graph(G):
    nx.draw(G, with_labels=True)
    plt.show()


if __name__ == "__main__":
    show_graph(read_graph(sys.argv[1]))


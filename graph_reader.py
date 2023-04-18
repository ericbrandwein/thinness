import networkx as nx


GRAPHS_DIR = "adjlists"
GRAPHS_FILE_EXTENSION = ".adjlist"


def read_graph(filename):
    path = f"{GRAPHS_DIR}/{filename}{GRAPHS_FILE_EXTENSION}"
    print("Reading graph from file:", path)
    return nx.read_adjlist(path, nodetype=int)
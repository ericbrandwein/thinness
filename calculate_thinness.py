import networkx as nx
import matplotlib.pyplot as plt

G = nx.read_edgelist("graph.txt")
nx.draw(G, with_labels=True)
plt.show()


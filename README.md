# Graph Thinness algorithms

Calculate the thinness and proper thinness of a graph, and obtain an optimal (strongly) consistent solution.

Includes two exact algorithms:
- One is a branch and bound algorithm with some greedy optimizations.
- The other one uses the Z3 SMT solver to obtain a solution from an integer constraints formulation.

The B&B algorithm is much faster than the other one, but currently does not support calculating the proper thinness.

## Requirements
- Python 3
- SageMath
- pipenv

## Setting up the environment
- Run `pipenv --site-packages --dev install`
- Run `pipenv run build` to compile the `.pyx` files

Done! Now you can import the algorithms in any Python script in this directory. For example:

```
from sage.graphs.graph_generators import graphs
from thinness.branch_and_bound import calculate_thinness

for graph in graphs(8):
    print(graph.graph6_string(), calculate_thinness(graph))
```

## Classification of small graphs
The minimal graphs for each thinness and proper thinness value for graphs with up to 10 vertices can be found in the CSV files in [data/](data/).

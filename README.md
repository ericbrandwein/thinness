# Graph Thinness algorithms

Calculate the thinness and proper thinness of a graph, and obtain an optimal (strongly) consistent solution.

Includes two exact algorithms:
- One is a branch and bound algorithm with some greedy optimizations.
- The other one uses the Z3 SMT solver to obtain a solution from an integer constraints formulation.

The B&B algorithm is much faster than the other one, but currently does not support calculating the proper thinness.

## Requirements
- Python 3.10
- SageMath >=10.0
- pipenv

## Setting up the environment
- Run `pipenv --site-packages install`
- Run `pipenv run build` to compile the `.pyx` files

Done! Now you can import the algorithms in any Python script in this directory. For example:

```
from sage.graphs.graph_generators import graphs
from thinness.branch_and_bound import calculate_thinness

for graph in graphs(8):
    print(graph.graph6_string(), calculate_thinness(graph))
```

## Using Docker

If you cannot install the dependencies for some reason (for example, Ubuntu doesn't have Sagemath 10.0 yet), you can use the provided Dockerfile to build a container with all the dependencies. You will need to have Docker and `docker-buildx` installed. In Debian/Ubuntu:

```
sudo apt install docker docker-buildx
```

In the root directory of the project, run:

```bash
sudo docker build -t thinness_sage . # This can take a while
```
This will build the image with the name `thinness_sage`. You can then run the container with:

```bash
sudo docker run --mount type=bind,source=.,target=/thinness-sage -it thinness_sage
```

Once inside the container, run `pipenv run build` and done! You have a working environment where you can run your scripts:

```bash
pipenv shell
python -m thinness.para_manu
```

## Classification of small graphs
The minimal graphs for each thinness and proper thinness value for graphs with up to 10 vertices can be found in the CSV files in [data/](data/).

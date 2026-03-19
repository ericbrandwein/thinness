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

Done! Now you can import the algorithms in any Python script in this directory. For example, you can put this into a file `thinness/test.py`:

```
from sage.graphs.graph_generators import graphs
from thinness.branch_and_bound import calculate_thinness

for graph in graphs(8):
    print(graph.graph6_string(), calculate_thinness(graph))
```

and run it with 
```bash
$ pipenv shell
$ python -m thinness.test
```

## Using Docker

If you cannot install the dependencies for some reason (for example, Ubuntu doesn't have Sagemath 10.0 yet), you can use the provided Dockerfile to build a container with all the dependencies. You will need to have Docker and `docker-buildx` installed. In Debian/Ubuntu:

```
sudo snap install docker
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

## Common issues

If you're getting this error in Arch Linux when trying to run a python script that imports some sage library:

```
AttributeError: partially initialized module 'sage.rings.integer_ring' from '/usr/lib/python3.14/site-packages/sage/rings/integer_ring.cpython-314-x86_64-linux-gnu.so' has no attribute 'ZZ' (most likely due to a circular import)
```

Try putting `from sage import all` at the top of your script. This forces sage to initialize the whole library before running your script.
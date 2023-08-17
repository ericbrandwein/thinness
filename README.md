# On the thinness and proper thinness of a graph

This code was written during the research of [BD19](https://doi.org/10.1016/j.dam.2018.03.072), and depends on [SageMath](https://www.sagemath.org/) version 9 or later.

## How to use

The test suite is run via `sage -t *.sage`.

As an example of how to use these functions in the Sage interactive shell:

```
sage: load('thinness.sage')
sage: load('proper-thinness.sage')
sage: thinness(graphs.ClawGraph())
(1, [1, 2, 0, 3], [[0, 1, 2, 3]])
sage: proper_thinness(graphs.ClawGraph())
(2, [0, 1, 2, 3], [[0, 3], [1, 2]])
sage: thinness(graphs.PetersenGraph(), random_permutations=1000)
(4, [3, 0, 4, 7, 1, 5, 6, 2, 8, 9], [[0, 5, 6, 9], [1, 2, 8], [3], [4, 7]])
sage: proper_thinness(graphs.PetersenGraph(), random_permutations=1000)
(5, [8, 2, 6, 1, 4, 3, 7, 0, 9, 5], [[0, 1], [3, 5], [4, 6], [9, 2], [7, 8]])
```
Some comments:

- The output by default includes a certificate of the value, i.e. an ordering and a partition of the vertex set. That can be disabled by passing `certificate = False`.
- To accelerate the computation you can use the `lower_bound` parameter when you know a lower bound for the (proper) thinness of the graph.
- When the `random_permutations` parameter is used, an approximation of the value is performed instead of the exact calculation.

## Classification of small graphs

We classified all connected graphs of up to 8 vertices with respect to their thinness and proper thinness. We only list the minimal graphs for each (proper) thinness value, with respect to the induced subgraph partial order.

We use multiple ways of referencing a graph:

- When available, we show the name from [ISGCI "smallgraphs" website](https://www.graphclasses.org/smallgraphs.html).
- We uploaded all of these graphs to [The House of Graphs](https://hog.grinvin.org/), so the link is given.
- We provide a graph6 code for the graph, for a vertex ordering corresponding to an optimal (proper) thin representation.

See the list of minimal graphs for each [thinness](small-graphs-thinness.md) and [proper thinness](small-graphs-proper-thinness.md) value. All this data is available [in CSV format too](data/).

## Algorithms

These algorithms are proven correct in Theorem 2 of [BD19](https://doi.org/10.1016/j.dam.2018.03.072). The current implementation uses a graph coloring algorithm for general graphs, which runs in exponential time. This is suboptimal, because the graph to be colored is a co-comparability graph and so can be colored in polynomial time.

In order to make it useful for larger graphs, we should switch to a polynomial time algorithm, e.g. the one of [G77](https://doi.org/10.1007/BF02253207).

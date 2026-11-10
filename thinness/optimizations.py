"""Optimizations of the branch and bound for thinness, which can be disabled to measure their effect.

Disabling an optimization only makes the search explore more, so the thinness
found is the same with any combination of them.
"""
import enum
import functools
import operator


class Optimization(enum.IntFlag):
    # Each connected component is searched on its own, and the largest thinness
    # found so far is a lower bound for the rest.
    COMPONENTS = 1 << 0
    # The vertex separation number is an upper bound.
    VERTEX_SEPARATION_BOUND = 1 << 1
    # Only one vertex of each orbit of the automorphism group starts the order.
    SYMMETRY = 1 << 2
    # States that were already searched are not searched again.
    SEEN_STATES = 1 << 3
    # A vertex with the same suffix neighbors as a part is added to it without branching.
    GREEDY_EXISTING_PART = 1 << 4
    # Of two parts a vertex can be added to, if the suffix neighbors of one contain
    # those of the other, it is only added to the first one.
    PART_DOMINANCE = 1 << 5
    # A vertex is not added to a part if another vertex that can be added to it
    # has suffix neighbors contained in its own.
    VERTEX_DOMINANCE = 1 << 6
    # A vertex that can be added to an existing part doesn't start a new one.
    NEW_PART_ONLY_IF_NEEDED = 1 << 7
    # A vertex doesn't start a new part if another vertex that can start it has
    # suffix neighbors contained in its own. This also makes a vertex without
    # suffix neighbors the only one to start it, if there is one.
    NEW_PART_DOMINANCE = 1 << 8
    # A vertex that another vertex unlocks is not branched on, see
    # `_ignore_unlocked_vertices` in the branch and bound.
    UNLOCKING = 1 << 9


ALL_OPTIMIZATIONS = functools.reduce(operator.or_, Optimization)

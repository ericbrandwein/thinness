"""Optimizations of the branch and bound for proper thinness, which can be disabled to measure their effect.

Disabling an optimization only makes the search explore more, so the proper
thinness found is the same with any combination of them.
"""
import enum
import functools
import operator


class Optimization(enum.IntFlag):
    # Each connected component is searched on its own.
    COMPONENTS = 1 << 0
    # The thinness is a lower bound.
    THINNESS_LOWER_BOUND = 1 << 1
    # The best solution for a few vertex orders, see `heuristic_solution`, is an upper bound.
    HEURISTIC_UPPER_BOUND = 1 << 2
    # Only one vertex of each orbit of the automorphism group starts the order.
    SYMMETRY = 1 << 3
    # States that were already searched are not searched again.
    SEEN_STATES = 1 << 4
    # A vertex that can be added to an existing part for free is added without
    # branching, see `_find_free_part_for_vertex` in the branch and bound.
    GREEDY_EXISTING_PART = 1 << 5
    # A vertex that can start a new part for free starts it without branching.
    GREEDY_NEW_PART = 1 << 6
    # Of the parts a vertex can be added to that dominate each other, it is only
    # added to one, see `_is_part_dominated` in the branch and bound.
    PART_DOMINANCE = 1 << 7


ALL_OPTIMIZATIONS = functools.reduce(operator.or_, Optimization)
DEFAULT_OPTIMIZATIONS = ALL_OPTIMIZATIONS

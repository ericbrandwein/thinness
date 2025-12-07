from itertools import permutations


def non_betweenness(elements, prohibitions):
    """
    Return `True` if there exists a permutation of `elements` that does not
    contain any of the ordered triples in `prohibitions`.
    """
    for permutation in permutations(elements):
        for a, b, c in prohibitions:
            if (permutation.index(a) < permutation.index(b) < permutation.index(c) or
                permutation.index(c) < permutation.index(b) < permutation.index(a)):
                break
        else:
            return True
    return False
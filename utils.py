from itertools import combinations, chain

def all_subsets(iterable):
    s = list(iterable)
    return chain.from_iterable(combinations(s, r) for r in range(len(s)+1))


def insertions(iterable, element):
    for i in range(len(iterable) + 1):
        yield iterable[:i] + [element] + iterable[i:]


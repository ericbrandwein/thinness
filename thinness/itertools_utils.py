import itertools

def skip_first(iterator, elements):
    next(itertools.islice(iterator, elements, elements), None)


load('helpers.sage')
load('cocomparability-coloring.sage')

def graphs_by_proper_thinness(n, *, minimal_only=True):
    r""" Calculates the proper thinness of connected non-isomorphic graphs up to `n` vertices.

    TESTS::

        sage: {k: len(l) for k, l in graphs_by_proper_thinness(4, minimal_only=False).items()}
        {1: 7, 2: 2}
        sage: {k: len(l) for k, l in graphs_by_proper_thinness(5, minimal_only=False).items()}
        {1: 17, 2: 13}
        sage: {k: len(l) for k, l in graphs_by_proper_thinness(6, minimal_only=False).items()}
        {1: 43, 2: 96, 3: 3}
        sage: {k: len(l) for k, l in graphs_by_proper_thinness(4).items()}
        {1: 1, 2: 2}
        sage: {k: len(l) for k, l in graphs_by_proper_thinness(5).items()}
        {1: 1, 2: 3}
        sage: {k: len(l) for k, l in graphs_by_proper_thinness(6).items()}
        {1: 1, 2: 6, 3: 3}
        sage: [G for G in _connected_graphs_upto(6) if _is_proper_interval(G)] == graphs_by_proper_thinness(6, minimal_only=False)[1]
        True
    """
    graphs_dict = {}
    for G in _connected_graphs_upto(n):
        lower_bound = _find_lower_bound(G, graphs_dict)
        k = proper_thinness(G, certificate=False, lower_bound=lower_bound)
        graphs_dict.setdefault(k, [])
        if minimal_only:
            if not _has_induced_subgraph(G, graphs_dict[k]):
                graphs_dict[k].append(G)
        else:
            graphs_dict[k].append(G)
    return graphs_dict

def graphs_by_proper_thinness_precomputed(n=8, *, minimal_only=True):
    r""" Outputs the same as `graphs_by_proper_thinness` by using precomputed values.

    TESTS::

        sage: Counter([G.canonical_label() for G in graphs_by_proper_thinness_precomputed(6)[2]]) == Counter([G.canonical_label() for G in graphs_by_proper_thinness(6)[2]])
        True
        sage: Counter([G.canonical_label() for G in graphs_by_proper_thinness_precomputed(6)[3]]) == Counter([G.canonical_label() for G in graphs_by_proper_thinness(6)[3]])
        True
        sage: len([G for G in graphs_by_proper_thinness_precomputed(6, minimal_only=False)[1] if len(G.vertices()) == 6])
        26
    """
    if n > 8:
        raise ValueError('There is no precomputed data for this value of n')
    input_dict = {}
    for k in range(2, 5):
        input_dict[k] = _load_graphs_from_csv('data/proper-thinness-{}.csv'.format(k))
    output_dict = {}
    if minimal_only:
        for k in range(2, 5):
            output_dict[k] = [G for G in input_dict[k] if len(G.vertices()) <= n]
    else:
        for G in _connected_graphs_upto(n):
            k = _find_lower_bound(G, input_dict)
            output_dict.setdefault(k, [])
            output_dict[k].append(G)
    return output_dict

def _is_proper_interval(G):
    return G.is_interval() and not G.subgraph_search(graphs.ClawGraph(), induced=True)

def proper_thinness(G, *, lower_bound=1, certificate=True, random_permutations=None):
    r""" Calculates the proper thinness of graph G.

    TESTS::

        sage: proper_thinness(graphs.CycleGraph(3), certificate=False)
        1
        sage: proper_thinness(graphs.ClawGraph(), certificate=False)
        2
        sage: proper_thinness(graphs.CycleGraph(4), certificate=False)
        2
        sage: proper_thinness(graphs.CycleGraph(7).complement(), certificate=False)
        3
        sage: proper_thinness(graphs.PetersenGraph(), certificate=False, random_permutations=100)
        5
    """
    min_chi, min_pi, min_partition = +Infinity, [], []
    for pi in _iterate_permutations(G.vertices(), random_permutations):
        H = _proper_thinness_create_restrictions_graph(G, pi)
        partition = cocomparability_coloring(H)
        chi = len(partition)
        if chi < min_chi:
            min_chi, min_pi, min_partition = chi, pi, partition
            if min_chi == lower_bound:
                break
    if certificate:
        return (min_chi, min_pi, min_partition)
    else:
        return min_chi

def _proper_thinness_cannot_be_in_same_class(G, pi, i, j):
    for k in range(0, i):
        if G.has_edge(pi[j], pi[k]) and not G.has_edge(pi[i], pi[k]):
            return True
    for k in range(j+1, len(G)):
        if G.has_edge(pi[i], pi[k]) and not G.has_edge(pi[j], pi[k]):
            return True
    return False

def _proper_thinness_create_restrictions_graph(G, pi):
    n = len(G)
    H = Graph(n)
    for i in range(0,n):
        for j in range(i+1,n):
            if _proper_thinness_cannot_be_in_same_class(G,pi,i,j):
                H.add_edge(pi[i],pi[j])
    return H

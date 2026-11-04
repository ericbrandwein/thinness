# TODO

## Proper thinness branch and bound

### Unlocked vertices

Port the unlock rule of the thinness branch and bound (`_ignore_unlocked_vertices` in
`thinness/branch_and_bound.pyx`): when branching on the next vertex `v`, skip `v` this
round if some other suffix vertex `u` can be added to a part so that the part's suffix
neighbors only gain `v`, since putting `u` and then `v` is always at least as good as
putting `v` next.

- In thinness, `u` unlocks `v` when part `P` is available for `u` and
  `|N_S(P)| = |N_S(u)| - 1`; the unlockers are recorded while computing the available
  parts. Ignored vertices can't unlock others, so that two vertices can't cause each
  other to be ignored.
- For proper thinness this needs its own soundness proof, because adding `u` to `P`
  also forbids `P` for some suffix vertices (those adjacent to a prefix non neighbor of
  `u`), and the swapped order changes which vertices are in the prefix when `v` is
  added. Probably needs a condition on the forbidden vertices, like the free-move
  greedy rule and part dominance did.

### 64-bit version

Port `thinness/branch_and_bound_64.pyx`: for graphs of at most 64 vertices, every set
of vertices or parts is a `uint64_t`, with the bitset version as fallback for larger
graphs. In thinness it gave about 4x.

- `SeenStates.contains_or_add_words` only supports one set per part, so it needs
  `sets_per_part = 2` support (suffix neighbors and forbidden vertices of each part).
- Test the fallback like `test_thinness_of_random_graphs_with_bitsets_against_reference`
  does, patching the vertex limit to 0.

### Other thinness rules not ported

`_can_other_vertex_be_prepended_freely` and `_can_other_vertex_open_new_part_freely`,
which also need soundness proofs that take the forbidden vertices into account.

## Both branch and bounds

### Lower bounds per node

Neither branch and bound bounds the number of parts that a node still needs. At each
node, estimate how many more parts the suffix needs at least, and prune when
`parts_used` plus that estimate is more than the upper bound.

The proper thinness stats showed that this is where the time goes: on a random graph
with 15 vertices the heuristic found an optimal solution, but the number of nodes didn't
change, as the search still has to prove that one part less is impossible. Upper bounds
don't help with that, per node lower bounds do.

Ideas: suffix vertices for which no existing part is available, and that can't share a
part with each other whatever the rest of the order is.

### Global lower bounds

For proper thinness, the thinness is the only lower bound used. Where the proper
thinness is larger (crown 7, cylinder 3x7, random graphs), a better one would let the
search stop at the first optimal solution.

## Measuring

The search counters and `search_stats.py` were removed. To see where the search spends
its time again (nodes, memo hits, greedy additions, dominated parts), add counters to
`_Context` temporarily and run each case with the rules on and off.

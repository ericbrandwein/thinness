"""Generates the minimal graphs for thinness and proper thinness, order by order.

A graph is minimal for a parameter if every proper induced subgraph has a
smaller value. Both parameters are hereditary, so it is enough to compare the
value of a graph with the largest value of the graphs with one vertex less,
which are looked up in the tables of the smaller orders (see `classify`).
Minimal graphs are connected, as the value of a graph is the largest value of
its components, so only connected graphs are generated.

    python -m minimal_graphs.generate MAX_ORDER [--output DIR] [--processes P] [--chunks C]

For each order k it writes to the output directory:
- `order-k.table`: the table of the connected graphs of order k, except for the
  largest order `classify` supports, as no table is needed above it.
- `order-k.csv`: the minimal graphs of order k, as rows graph6,parameter,value.
- `order-k.json`: the number of graphs, the ones whose proper thinness is more
  than one above the largest without a vertex, and the seconds taken.
At the end, `thinness-v.csv` and `proper-thinness-v.csv` have the graph6 of the
minimal graphs of value v of every order, under the header `graph6`.

geng generates the graphs of each order in chunks with its res/mod argument.
Orders and chunks whose files exist are skipped, so an interrupted run resumes
where it stopped.
"""
import argparse
import array
import collections
import contextlib
import json
import mmap
import multiprocessing
import os
import shutil
import subprocess
import time
from collections.abc import Iterator

import numpy as np

from minimal_graphs.classify import Classifier, MAX_ORDER

THINNESS = 'thinness'
PROPER_THINNESS = 'proper-thinness'
DEFAULT_OUTPUT_DIR = 'data/generated'
# Smaller orders are generated in a single chunk.
MIN_ORDER_FOR_CHUNKS = 9
# The rest are only in the order's json file.
MAX_JUMPS_PRINTED = 10

_classifier = None


def generate(max_order: int, output_dir: str, processes: int, chunks: int):
    if not 1 <= max_order <= MAX_ORDER:
        raise ValueError(f'The order must be between 1 and {MAX_ORDER}')
    os.makedirs(output_dir, exist_ok=True)
    for order in range(1, max_order + 1):
        stats_path = _order_path(output_dir, order, 'json')
        if os.path.exists(stats_path):
            print(f'Order {order}: already generated')
            continue
        mod = chunks if order >= MIN_ORDER_FOR_CHUNKS else 1
        _generate_order(output_dir, order, mod, processes)
        _print_order_stats(output_dir, order)
    _write_lists(output_dir, max_order)


def _generate_order(output_dir: str, order: int, mod: int, processes: int):
    chunk_dir = os.path.join(output_dir, f'order-{order}-chunks')
    os.makedirs(chunk_dir, exist_ok=True)
    pending = [
        (chunk_dir, order, res, mod)
        for res in range(mod)
        if not os.path.exists(_chunk_path(chunk_dir, res, mod, 'json'))
    ]
    if pending:
        with multiprocessing.Pool(
            min(processes, len(pending)),
            initializer=_load_classifier,
            initargs=(output_dir, order),
        ) as pool:
            for done, _ in enumerate(pool.imap_unordered(_classify_chunk, pending), start=1):
                print(f'Order {order}: {done}/{len(pending)} chunks', end='\r', flush=True)
        print()
    _merge_chunks(output_dir, chunk_dir, order, mod)
    shutil.rmtree(chunk_dir)


def load_tables(output_dir: str, order: int) -> dict[int, mmap.mmap]:
    """The tables needed for the graphs of the order, mapped to memory so that processes share them."""
    tables = {}
    for smaller_order in range(1, order):
        with open(_order_path(output_dir, smaller_order, 'table'), 'rb') as file:
            tables[smaller_order] = mmap.mmap(file.fileno(), 0, access=mmap.ACCESS_READ)
    return tables


def _load_classifier(output_dir: str, order: int):
    global _classifier
    _classifier = Classifier(load_tables(output_dir, order))


def _classify_chunk(chunk: tuple[str, int, int, int]):
    chunk_dir, order, res, mod = chunk
    start = time.monotonic()
    table = array.array('Q')
    rows = []
    graphs = 0
    proper_thinness_jumps = []
    geng = subprocess.Popen(['geng', '-cq', str(order), f'{res}/{mod}'], stdout=subprocess.PIPE)
    for line in geng.stdout:
        graph6 = line.rstrip(b'\n')
        key, packed_order, thinness, proper_thinness, largest_thinness, largest_proper_thinness = _classifier.classify(graph6)
        graphs += 1
        if order < MAX_ORDER:
            table.append(key)
            table.append(packed_order)
        # K1 is the only minimal graph of value 1, so it isn't listed, as in `data`.
        if thinness > max(largest_thinness, 1):
            rows.append(f'{graph6.decode()},{THINNESS},{thinness}\n')
        if proper_thinness > max(largest_proper_thinness, 1):
            rows.append(f'{graph6.decode()},{PROPER_THINNESS},{proper_thinness}\n')
        if proper_thinness > largest_proper_thinness + 1:
            proper_thinness_jumps.append(graph6.decode())
    if geng.wait() != 0:
        raise RuntimeError(f'geng failed with exit code {geng.returncode}')

    with _atomic_open(_chunk_path(chunk_dir, res, mod, 'table'), 'wb') as file:
        table.tofile(file)
    with _atomic_open(_chunk_path(chunk_dir, res, mod, 'csv'), 'w') as file:
        file.writelines(rows)
    # Written last, as it marks the chunk as done.
    with _atomic_open(_chunk_path(chunk_dir, res, mod, 'json'), 'w') as file:
        json.dump({
            'graphs': graphs,
            'proper_thinness_jumps': proper_thinness_jumps,
            'seconds': time.monotonic() - start,
        }, file)


def _merge_chunks(output_dir: str, chunk_dir: str, order: int, mod: int):
    if order < MAX_ORDER:
        tables = [np.fromfile(_chunk_path(chunk_dir, res, mod, 'table'), dtype=np.uint64) for res in range(mod)]
        # Pairs of words, sorted by the first one.
        entries = np.concatenate(tables).reshape(-1, 2)
        with _atomic_open(_order_path(output_dir, order, 'table'), 'wb') as file:
            entries[np.argsort(entries[:, 0])].tofile(file)

    with _atomic_open(_order_path(output_dir, order, 'csv'), 'w') as file:
        for res in range(mod):
            with open(_chunk_path(chunk_dir, res, mod, 'csv')) as chunk_file:
                shutil.copyfileobj(chunk_file, file)

    stats = {'graphs': 0, 'proper_thinness_jumps': [], 'seconds': 0}
    for res in range(mod):
        with open(_chunk_path(chunk_dir, res, mod, 'json')) as file:
            for key, value in json.load(file).items():
                stats[key] += value
    # Written last, as it marks the order as done.
    with _atomic_open(_order_path(output_dir, order, 'json'), 'w') as file:
        json.dump(stats, file)


def _print_order_stats(output_dir: str, order: int):
    with open(_order_path(output_dir, order, 'json')) as file:
        stats = json.load(file)
    minimal = collections.Counter((parameter, value) for _, parameter, value in _read_minimal_rows(output_dir, order))
    jumps = stats['proper_thinness_jumps']
    jump_examples = f': {" ".join(jumps[:MAX_JUMPS_PRINTED])}' if jumps else ''
    print(
        f'Order {order}: {stats["graphs"]:,} graphs in {stats["seconds"]:.1f} CPU seconds,',
        f'{len(jumps)} with proper thinness more than one above the largest without a vertex{jump_examples}.',
        'Minimal graphs:',
        ', '.join(f'{parameter} {value}: {count:,}' for (parameter, value), count in sorted(minimal.items())) or 'none',
    )


def _write_lists(output_dir: str, max_order: int):
    # Written as the rows are read, as there may be too many to keep in memory.
    with contextlib.ExitStack() as stack:
        files = {}
        for order in range(1, max_order + 1):
            for graph6, parameter, value in _read_minimal_rows(output_dir, order):
                if (parameter, value) not in files:
                    path = os.path.join(output_dir, f'{parameter}-{value}.csv')
                    files[parameter, value] = stack.enter_context(_atomic_open(path, 'w'))
                    files[parameter, value].write('graph6\n')
                files[parameter, value].write(f'{graph6}\n')


def _read_minimal_rows(output_dir: str, order: int) -> Iterator[tuple[str, str, int]]:
    """The graph6, parameter and value of each minimal graph of the order."""
    with open(_order_path(output_dir, order, 'csv')) as file:
        for line in file:
            graph6, parameter, value = line.rstrip('\n').split(',')
            yield graph6, parameter, int(value)


def _order_path(output_dir: str, order: int, extension: str) -> str:
    return os.path.join(output_dir, f'order-{order}.{extension}')


def _chunk_path(chunk_dir: str, res: int, mod: int, extension: str) -> str:
    return os.path.join(chunk_dir, f'chunk-{res}-of-{mod}.{extension}')


class _atomic_open:
    """Opens a temporary file that replaces `path` when closed without errors."""

    def __init__(self, path: str, mode: str):
        self.path = path
        self.temporary_path = f'{path}.tmp'
        self.file = open(self.temporary_path, mode)

    def __enter__(self):
        return self.file

    def __exit__(self, exception_type, exception, traceback):
        self.file.close()
        if exception_type is None:
            os.replace(self.temporary_path, self.path)
        else:
            os.remove(self.temporary_path)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('max_order', type=int)
    parser.add_argument('--output', default=DEFAULT_OUTPUT_DIR)
    parser.add_argument('--processes', type=int, default=os.cpu_count())
    parser.add_argument('--chunks', type=int, default=4 * os.cpu_count())
    arguments = parser.parse_args()
    generate(arguments.max_order, arguments.output, arguments.processes, arguments.chunks)

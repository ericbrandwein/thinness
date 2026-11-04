from sage import all
import textwrap
from linetimer import CodeTimer
from cysignals.alarm import alarm, cancel_alarm, AlarmInterrupt

from sage.graphs.graph_generators import graphs
from sage.graphs.graph import Graph
from sage.misc.randstate import set_random_seed

from proper_thinness.branch_and_bound import calculate_proper_thinness
from thinness.time_branch_and_bound import crown_graph, cylinder_graph

# A graph that takes longer than this is stopped, and the larger graphs of its family are skipped.
MAX_SECONDS_PER_GRAPH = 30
TIMEOUT = 'timeout'


def time_crown_graphs():
    for n in range(2, 13):
        result = time_calculation(crown_graph(n))
        print(textwrap.indent(text=f'{n}:\t{result}', prefix='  '), flush=True)
        if result == TIMEOUT:
            break


def time_random_graphs():
    for n in range(10, 20):
        print(textwrap.indent(text=f'{n}:', prefix='  '), flush=True)
        timed_out = False
        for density in [0.2, 0.5, 0.8]:
            m = n*(n-1)//2 * density
            times = []
            for _ in range(10):
                graph = graphs.RandomGNM(n, m)
                result = time_calculation(graph)
                if result == TIMEOUT:
                    timed_out = True
                    break
                times.append(result[0])
            average = TIMEOUT if timed_out else sum(times)/len(times)
            print(textwrap.indent(text=f'density {density}: {average}', prefix='    '), flush=True)
            if timed_out:
                return


def time_complement_of_nK2():
    for n in range(1, 14):
        result = time_calculation((graphs.CompleteGraph(2) * n).complement())
        print(textwrap.indent(text=f'{n}:\t{result}', prefix='  '), flush=True)
        if result == TIMEOUT:
            break


def time_grid_graphs():
    for rows in range(2, 9):
        for cols in range(2, rows + 1):
            result = time_calculation(graphs.Grid2dGraph(rows, cols))
            print(textwrap.indent(text=f'{rows}x{cols}:\t{result}', prefix='  '), flush=True)
            if result == TIMEOUT:
                return


def time_cylinder_graphs():
    for rows in range(2, 9):
        for columns in range(2, 9):
            result = time_calculation(cylinder_graph(rows, columns))
            print(textwrap.indent(text=f'{rows}x{columns}:\t{result}', prefix='  '), flush=True)
            if result == TIMEOUT:
                return


def time_calculation(graph: Graph) -> tuple[float, int] | str:
    """The time taken and the proper thinness, or TIMEOUT if it takes longer than MAX_SECONDS_PER_GRAPH."""
    code_timer = CodeTimer(silent=True)
    alarm(MAX_SECONDS_PER_GRAPH)
    try:
        with code_timer:
            proper_thinness = calculate_proper_thinness(graph, max_seen_entries=1_600_000, max_prefix_length=20)
    except AlarmInterrupt:
        return TIMEOUT
    finally:
        cancel_alarm()
    return code_timer.took / 1000, proper_thinness


if __name__ == '__main__':
    print("Crown graphs:")
    time_crown_graphs()

    set_random_seed(0)
    print("Random GNM graphs:")
    time_random_graphs()

    print("Complement of n*K2 graphs:")
    time_complement_of_nK2()

    print("Grid graphs:")
    time_grid_graphs()

    print("Cylinder graphs:")
    time_cylinder_graphs()

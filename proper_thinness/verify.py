import thinness


def verify_solution(graph, solution: thinness.ConsistentSolution):
    reversed_solution = thinness.ConsistentSolution(
        order=list(reversed(solution.order)),
        partition=list(reversed(solution.partition))
    )
    return thinness.verify.verify_solution(graph, solution) and thinness.verify.verify_solution(graph, reversed_solution)


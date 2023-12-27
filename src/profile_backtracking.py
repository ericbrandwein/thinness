import cProfile
import backtracking


def profile():
    backtracking.solve_graphs(10)


cProfile.runctx("profile()", globals(), locals(), "src/profile_backtracking.py.prof")

from backtracking import solve_graphs

for i in range(1, 20):
    print(f"Number of graphs with {i} vertices: {len(solve_graphs(i))}")
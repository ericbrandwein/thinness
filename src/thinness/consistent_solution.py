class ConsistentSolution:
    def __init__(self, order: list, partition: list[set]) -> None:
        self.order = order
        self.partition = partition
        self.thinness = len(partition)

    def part_of(self, vertex) -> int:
        for part, vertices in enumerate(self.partition):
            if vertex in vertices:
                return part
        return None

    def __str__(self):
        return f'Thinness: {self.thinness}, Order: {self.order}, Partition: {self.partition}'

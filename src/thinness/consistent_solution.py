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

    @staticmethod
    def from_model(model, variables):
        order = ConsistentSolution._order_from_model(model, variables) 
        partition = ConsistentSolution._partition_from_model(model, variables)
        return ConsistentSolution(order, partition)

    @staticmethod
    def _order_from_model(model, variables):
        return sorted(variables.orders, key=lambda node: model[variables.orders[node]].as_long())

    @staticmethod
    def _partition_from_model(model, variables):
        thinness = model[variables.k_thin].as_long()
        partition = [set() for _ in range(thinness)]
        for node, part in variables.classes.items():
            partition[model[part].as_long() - 1].add(node)
        return partition

    def __str__(self):
        return f'Thinness: {self.thinness}, Order: {self.order}, Partition: {self.partition}'

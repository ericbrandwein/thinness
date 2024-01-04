import data

GRAPH_IMAGES_DIR = 'data/images/'
IMAGE_CSV_COLUMN_NAME = 'image'
IMAGE_FILE_EXTENSION = '.svg'


def graph_image_filename(graph):
    return GRAPH_IMAGES_DIR + graph.graph6_string() + IMAGE_FILE_EXTENSION


def save_graph_image(graph):
    graph.plot().save(graph_image_filename(graph))


def generate_graph_images():
    graphs_by_thinness = data.load_graphs_by_thinness()
    for graphs in graphs_by_thinness.values():
        for graph in graphs:
            save_graph_image(graph)


if __name__ == '__main__':
    generate_graph_images()
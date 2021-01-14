import argparse
from datetime import datetime
import fiona
import json
import logging
import os
import pyproj
import rtree
import shapely.geometry
import shapely.ops
import tqdm


LOGGER = logging.getLogger(__file__)
logging.basicConfig(level='INFO')


def __main__(args=None):
    parser = argparse.ArgumentParser('geomapping')
    parser.add_argument('filename1', help='filename of the first set of shapes')
    parser.add_argument('filename2', help='filename of the second set of shapes')
    parser.add_argument('output', help='filename for the output')
    # See https://epsg.io/27700
    parser.add_argument('--crs', default='epsg:27700', help='coordinate reference system in which '
                        'to evaluate intersections (defaults to the British National Grid '
                        'epsg:27700')
    parser.add_argument('--crs1', help='coordinate reference system of the first set of shapes '
                        '(inferred if omitted)')
    parser.add_argument('--crs2', help='coordinate reference system of the second set of shapes '
                        '(inferred if omitted)')
    args = parser.parse_args()

    # Get the coordinate system in which to evaluate intersections
    target_crs = pyproj.CRS(args.crs)

    # Load the data into memory
    filenames = [args.filename1, args.filename2]
    crss = [args.crs1, args.crs2]
    properties = []
    shapes = []
    for filename, source_crs in zip(filenames, crss):
        with fiona.open(filename) as fp:
            # Set up transformations for the data
            source_crs = pyproj.CRS(source_crs or fp.crs)
            transformer = pyproj.Transformer.from_crs(source_crs, target_crs, always_xy=True)

            properties_ = []
            shapes_ = []
            for item in tqdm.tqdm(fp, desc=f'loading from {filename}'):
                # Load and transform to the target coordinate system
                shape = shapely.geometry.shape(item['geometry'])
                shape = shapely.ops.transform(transformer.transform, shape)
                # Buffer the shape to ensure it's valid if required
                if not shape.is_valid:
                    shape = shape.buffer(0)
                shapes_.append(shape)

                # Store properties
                properties_.append(dict(item['properties']))
            properties.append(properties_)
            shapes.append(shapes_)
        LOGGER.info('loaded %d shapes from %s', len(shapes_), filename)

    # Evaluate areas for each shape
    areas = [[shape.area for shape in shapes_] for shapes_ in shapes]

    # Get reference and query shapes (reorder to ensure the larger number is put in the index)
    reference_shapes, query_shapes = shapes
    reorder = len(reference_shapes) < len(query_shapes)
    if reorder:
        reference_shapes, query_shapes = query_shapes, reference_shapes

    # Build a search tree to calculate overlaps
    index = rtree.Index()
    for i, shape in enumerate(reference_shapes):
        index.insert(i, shape.bounds)
    LOGGER.info('constructed rtree with %d elements', len(reference_shapes))

    # Run over the query shapes and find intersections
    intersections = []
    for j, shape in enumerate(tqdm.tqdm(query_shapes, desc='evaluating intersections')):
        for i in index.intersection(shape.bounds):
            intersection = reference_shapes[i].intersection(shape)
            if intersection.area:
                if reorder:
                    intersections.append((j, i, intersection.area))
                else:
                    intersections.append((i, j, intersection.area))
    num_possible_interactions = len(reference_shapes) * len(query_shapes)
    LOGGER.info('identified %d of %d possible intersections (%.2f%%)', len(intersections),
                num_possible_interactions, 100 * len(intersections) / num_possible_interactions)

    # Store the result
    result = {
        'metadata': {
            'timestamp': datetime.now().isoformat(),
            'args': vars(args),
        },
        'properties': properties,
        'areas': areas,
        'intersections': intersections,
    }
    directory = os.path.split(args.output)[0]
    if directory:
        os.makedirs(directory, exist_ok=True)
    with open(args.output, 'w') as fp:
        json.dump(result, fp, indent=2)


if __name__ == '__main__':
    __main__()

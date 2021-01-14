import arcgis
import argparse
import fiona
import json
import logging
import os
import pyproj


LOGGER = logging.getLogger(__file__)
logging.basicConfig(level=logging.INFO)


TYPE_LOOKUP = {
    'sqlTypeOther': 'str',
    'sqlTypeDouble': 'float',
}


def __main__(args=None):
    parser = argparse.ArgumentParser('download_arcgis_dataset')
    parser.add_argument('data_item', help='data item to download')
    parser.add_argument('output', help='filename for the output')
    parser.add_argument('--username', help='username for authentication')
    parser.add_argument('--password', help='password for authentication')
    parser.add_argument('--layer', help='name of the layer to download')
    args = parser.parse_args(args)

    gis = arcgis.gis.GIS(username=args.username, password=args.password)
    data_item = gis.content.get(args.data_item)
    os.makedirs(args.output, exist_ok=True)

    for layer in data_item.layers:
        name = layer.properties['name']
        if args.layer and args.layer != name:
            LOGGER.info('skipped layer %s', name)
            continue

        LOGGER.info('querying layer %s...', name)
        # Get things into the right format as GeoJSON
        features = json.loads(layer.query().to_geojson)['features']
        LOGGER.info('retrieved %d features for layer %s', len(features), name)

        # Get the coordinate system
        wkid = layer.properties['extent']['spatialReference']['wkid']
        crs = pyproj.CRS.from_authority('esri', wkid)

        # Generate a schema
        schema = {
            'geometry': features[0]['geometry']['type'],
            'properties': {field['name']: TYPE_LOOKUP.get(field['sqlType'], field['sqlType'])
                           for field in layer.properties['fields']}
        }

        # Save the data
        filename = os.path.join(args.output, f'{name}.geojson')
        with fiona.open(filename, 'w', crs=f'epsg:{crs.to_epsg()}', schema=schema,
                        driver='GeoJSON') as fp:
            fp.writerecords(features)


if __name__ == "__main__":
    __main__()

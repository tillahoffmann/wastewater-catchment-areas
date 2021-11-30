from tqdm import tqdm
import os
import shutil
from urllib import request

ROOT = 'data/eea.europa.eu'

# Create a table of all urls.
table = {
    i + 1: f'https://www.eea.europa.eu/data-and-maps/data/waterbase-uwwtd-'
    f'urban-waste-water-treatment-directive-{i}/waterbase-uwwtd/waterbase-uwwtd-csv-files/'
    'at_download/file' for i in range(1, 8)
}
table[1] = 'https://www.eea.europa.eu/data-and-maps/data/waterbase-uwwtd-urban-' \
    'waste-water-treatment-directive/waterbase-uwwtd/waterbase-uwwtd-csv-files/at_download/file'


# Download all eight datasets.
for version, url in tqdm(table.items()):
    filename = None
    directory = os.path.join(ROOT, f'waterbase_v{version}_csv')
    if os.path.isdir(directory):
        print(f'{directory} already exists, skipping...')
        continue

    try:
        filename, _ = request.urlretrieve(url)
        target = ROOT

        # Depending on the version, the archive needs to be unpacked differently.
        if version in {1, 2, 3, 4, 5}:
            target = directory
        shutil.unpack_archive(filename, target, 'zip')

        # Version six has a different format and we need to rename the directory.
        if version == 6:
            shutil.move(os.path.join(ROOT, 'Waterbase_UWWTD_v6_csv'), directory)

        # Verify that this worked.
        if not os.path.isdir(directory):
            raise RuntimeError(f'could not download {directory}')
        print(f'downloaded {directory}.')
    finally:
        if os.path.isfile(filename):
            os.remove(filename)

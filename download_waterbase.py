from tqdm import tqdm
import os
import shutil
from urllib import request

ROOT = 'data/eea.europa.eu'
TABLE = {
    1: '20190617175711',
    2: '20190318143517',
    3: '20190617213458',
    4: '20190617213439',
    5: '20190616193603',
    6: '20210416204729',
    7: '20230316164226',
    8: '20230316164256',
}


def __main__():
    # Download all eight datasets.
    for version, key in tqdm(TABLE.items()):
        suffix = f'-{version - 1}' if version > 1 else ''
        url = f'https://web.archive.org/web/{key}if_/https://www.eea.europa.eu/data-and-maps/' \
            f'data/waterbase-uwwtd-urban-waste-water-treatment-directive{suffix}/waterbase-uwwtd/' \
            'waterbase-uwwtd-csv-files/at_download/file'
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
            if version in {6, 8}:
                shutil.move(os.path.join(ROOT, f'Waterbase_UWWTD_v{version}_csv'), directory)

            # Verify that this worked.
            if not os.path.isdir(directory):
                raise RuntimeError(f'could not download {directory}')
            print(f'downloaded {directory}.')
        except Exception as ex:
            print(f'failed to download version {version} from {url}: {ex}')
        finally:
            if filename and os.path.isfile(filename):
                os.remove(filename)


if __name__ == '__main__':
    __main__()

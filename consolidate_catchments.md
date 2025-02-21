---
jupyter:
  jupytext:
    text_representation:
      extension: .md
      format_name: markdown
      format_version: '1.3'
      jupytext_version: 1.16.7
  kernelspec:
    display_name: venv
    language: python
    name: python3
---

```python
import fiona
import os
import logging
from tqdm.notebook import tqdm
import shapely as sh
import shapely.geometry
import geopandas as gpd
import pandas as pd
from matplotlib import pyplot as plt
import matplotlib as mpl
import numpy as np
import collections
import hashlib

mpl.rcParams['figure.dpi'] = 144
mpl.style.use('scrartcl.mplstyle')
```

```python
# Define helper functions for processing the data.

def assert_in(*values, key=None):
    """
    Assert that the value belongs to a set of values.
    """
    def _wrapper(properties, value):
        assert value in values, f'{value} is not one of {values}'
        if key:
            properties[key] = value
    return _wrapper


def assert_unique(key=None, *, on_error='raise', exceptions=None):
    """
    Assert that the value is unique.
    """
    values = collections.Counter()
    exceptions = exceptions or set()
    def _wrapper(properties, value):
        if value in values and value not in exceptions:
            message = f'`{value}` is not a unique value and has occurred {values[value]} times'
            if on_error == 'raise':
                raise ValueError(message)
            elif on_error == 'warn':
                logging.warning(message)
            else:
                raise NotImplementedError

        values[value] += 1
        if key:
            properties[key] = value
    return _wrapper
```

```python
root = 'data/raw_catchments'
crs = 'epsg:27700'

# List of recognised catchment owners as supplied by Severn Trent (to make sure there aren't any
# unexpected values).
severn_trent_allowed_owners = [
    'STW', 'Hafren Dyfrdwy', 'Yorkshire Water', 'Anglian Water', 'Private', 'Welsh Water',
    'United Utilities', 'Thames Water', None,
]

def united_utilities_aggregation(catchments):
    """
    Function to aggregate United Utilities subcatchments into catchments at the treatment work
    level.
    """
    catchments['reference'] = catchments.reference.str.extract(r'(?P<prefix>UU-\d+-SC\d+-\w+)')
    assert catchments.reference.nunique() < len(catchments)
    return catchments.dissolve(by='reference').reset_index()


# Declare the schema we expect to see for all the different shapefiles. `None` means we acknowledge
# the field exists but ignore it in processing. We use the `postprocessor` function to apply
# transformations after loading the data, e.g. to aggregate subcatchments.
datasets = [
    {
        'company': 'scottish_water',
        'filename': 'scottish_water.zip/DOAs and WWTWs',
        'properties': {
            'doa_name': assert_unique('name', exceptions=[
                # This occurs twice, once for DOA000038 (which should probably be called Maxton)
                # and also for DOA002612 which actually has a road called 'Wellrig'.
                'Wellrig DOA'
            ]),
            # See postprocessor for exception.
            'doa_refere': assert_unique('reference', exceptions=['DOA000917']),
            'SHAPE_STAr': None,
            'wams_stw_n': None,
        },
        # This deals with the one repeated reference in the dataset due to a new development near Dunbar.
        'postprocessor': lambda x: x.dissolve(by='reference').reset_index(),
    },
    {
        'company': 'thames_water',
        'filename': 'thames_water.zip',
        'properties': {
            # We do not assert uniqueness for Thames Water Catchments because they have
            # provided us with detailed subcatchments (which belong to different STWs).
            'STWCODE': 'reference',
            'STWNAME': 'name',
            'SDACFOUL_1': None,
            'RECIEVINGS': None,
            'OBJECTID': None,
            'CREATIONUS': None,
            'DATECREATE': None,
            'DATEMODIFI': None,
            'LASTUSER': None,
            'SHAPEAREA': None,
            'SDACFOULBN': None,
            'DATEPOSTED': None,
            'GLOBALID': None,
            'SHAPE_AREA': None,
            'SHAPE_LEN': None,
        },
        'postprocessor': lambda x: x.dissolve(by='reference').reset_index(),
    },
    {
        'company': 'anglian_water',
        'filename': 'anglian_water.zip',
        'properties': {
            'AREANAME': assert_unique('name'),
            'AREASHORTC': assert_unique('reference'),
            'LIQUIDTYPE': None,
            'COLLECTION': None,
            'COLLECTIO1': None,
            'TREATMENTM': None,
            'TREATMENT1': None,
            'NOSINLINES': None,
            'NOSTERMINA': None,
            'NOSPROPS': None,
            'NOSDOMESTI': None,
            'NOSMIXEDPR': None,
            'NOSCOMMPRO': None,
            'HOMEPOPN': None,
            'HOUSEHOLDP': None,
            'DOMESTICPE': None,
            'HOLIDAYPE': None,
            'INSTITUTIO': None,
            'TRADEPE': None,
            'IMPORTPE': None,
            'EXPORTPE': None,
            'NOSSURFACE': None,
            'STWS_TOTNU': None,
            'SEWOUTFALL': None,
            'DATA_CONFI': None,
            'ID': None,
        }
    },
    {
        'company': 'northumbrian_water',
        'filename': 'northumbrian_water.zip/Export',
        'properties': {
            'NAME': assert_unique('name'),
            'ID': assert_unique('reference'),
            'GID': None,
            'APIC_STYLE': None,
            'APIC_SPACE': None,
            'APIC_STATE': None,
            'APIC_CDATE': None,
            'APIC_MDATE': None,
        }
    },
    {
        'company': 'severn_trent_water',
        'filename': 'severn_trent_water.zip',
        'properties': {
            # We allow non-unique names for private treatment works because they're not easily
            # identifiable.
            'CATCHMENT1': assert_unique('name', exceptions={
                'private SPS', 'private water works', 'private', 'private STW',
                'Surface water only', None,
            }),
            # Owner was useful in the original dataset because it allowed us to identify records
            # that weren't actually from Severn Trent Water. We'll have to do that manually now.
            # 'Owner': assert_in(*severn_trent_allowed_owners, key='owner'),
            'SU_REFEREN': assert_in('WwTw', 'WwTW', 'ST', None, 'Cess Pit'),
            'SAP_FLOC_I': 'reference',
            'OBJECTID': None,
            'CATCHMENT_': None,
            'CACI_2001': None,
            'CACI_20010': None,
            'CACI_2006': None,
            'CACI_2007': None,
            'CACI_2030': None,
            'PROPERTIES': None,
            'STATUS': None,
            'UPDATED': None,
            'SUGRAN': None,
            'COMMENT': None,
            'SAP_FLOC_D': None,
            'SHAPE_Leng': None,
            'STAR_ID': None,
            'WORKS_CODE': None,
            'WORKS_ID': None,
            'CREATED_DA': None,
            'MODIFIED_D': None,
            'MODIFIED_U': None,
            'CREATED_US': None,
            'JOB_ID': None,
            'QA_STATUS': None,
            'SAP_USER_S': None,
            'SAP_CLASS': None,
            'Shape_STAr': None,
            'Shape_STLe': None,
            'Shape_ST_1': None,
            'Shape_ST_2': None,
        },
    },
    {
        'company': 'southern_water',
        'filename': 'southern_water.zip',
        'properties': {
            'Site_Unit_': assert_unique('name'),
        }
    },
    {
        'company': 'united_utilities',
        'filename': 'united_utilities.zip',
        'properties': {
            'DA_CODE': assert_unique('reference'),
        },
        'postprocessor': united_utilities_aggregation,
    },
    {
        'company': 'welsh_water',
        'filename': 'welsh_water.zip',
        'properties': {
            'CATCHMENT_': assert_unique('name'),
            'TERMINAL_A': None,
            'Area_M': None,
        }
    },
    {
        'company': 'wessex_water',
        'filename': 'wessex_water.zip',
        'properties': {
            # There is a shared code because the Corsley Heath catchment comprises
            # two disjoint areas.
            'SITEID': assert_unique('reference', exceptions=[23390]),
            'NAME': 'name',
            'Comment': None,
        },
        # Wessex Water provide subcatchments, and we need to aggregate.
        'postprocessor': lambda x: x.dissolve(by='name').reset_index(),
    },
    {
        'company': 'yorkshire_water',
        'filename': 'yorkshire_water.zip/EIR - Wastewater Catchments',
        'properties':
        {
            'Company': assert_in('Yorkshire'),
            'Name': assert_unique('name'),
        }
    },
    {
        'company': 'south_west_water',
        'filename': 'south_west_water.shp',
        'properties': {
            "ID1": assert_unique("reference"),
            "EQUIPMENTN": None,
            "EQUIPMENTD": assert_unique("name"),
            "CATCHMENT1": None,
            "NOTES": None,
            "NOTEDATE": None,
            "CATCHMENT_": None,
        },
    },
]
assert len(datasets) == 11

# Iterate over all datasets, then over all features in each dataset, and validate the records.
parts = []
total = 0
for dataset in datasets:
    try:
        # Load the data. Probably should've used geopandas rather than the lower-level fiona. But
        # this implementation works for the time being.
        company_catchments = []
        path = os.path.join(root, dataset['filename'])
        if ".zip" in path:
            path = "zip://" + path
        with fiona.open(path) as fp:
            assert fp.crs['init'] == crs, 'dataset is not in the British National Grid projection'
            for feature in tqdm(fp, desc=dataset['company']):
                # Get the properties that we haven't declared and are thus unexpected. Then complain
                # if necessary.
                missing = {key: value for key, value in feature['properties'].items()
                            if key not in dataset['properties']}
                unexpected = set(feature['properties']) - set(dataset['properties'])
                if unexpected:
                    raise KeyError(f'could not remap unexpected fields {unexpected}')
                missing = set(dataset['properties']) - set(feature['properties'])
                if missing:
                    raise KeyError(f'missing expected fields {missing}')

                # Create a record for the consolidated dataset.
                properties = {
                    'company': dataset['company'],
                    'geometry': sh.geometry.shape(feature['geometry']),
                }

                # Process each feature and either store it if desired or apply a function to
                # validate the data.
                for key, value in feature['properties'].items():
                    key = dataset['properties'][key]
                    if callable(key):
                        key(properties, value)
                    elif key:
                        properties[key] = value

                # Check that we have *some* identifier.
                if not any([properties.get('reference'), properties.get('name')]):
                    logging.warning(f'{dataset["company"]} has feature without identifiers')

                # Store the record for future processing.
                company_catchments.append(properties)

        # Package the features in a geopandas frame and apply postprocessing steps if necessary.
        company_catchments = gpd.GeoDataFrame(company_catchments, crs=crs)
        total += len(company_catchments)
        postprocessor = dataset.get('postprocessor')
        if postprocessor:
            company_catchments = postprocessor(company_catchments)

        parts.append(company_catchments)
    except Exception as ex:
        raise RuntimeError(f'failed to process {dataset["filename"]}') from ex

catchments_raw = pd.concat(parts, ignore_index=True)
print(f'loaded {len(catchments_raw)} catchments with {total} shapes')

# Filter out catchments for Severn Trent that are odd.
fltr = (catchments_raw.company == 'severn_trent_water') & (
    (catchments_raw.reference == '0')  # These are private treatment works.
    | catchments_raw.reference.str.startswith('TW')  # These are from Thames Water ...
    | catchments_raw.reference.str.startswith('AW')  # ... Anglian Water ...
    | catchments_raw.reference.str.startswith('UU')  # ... United Utilities ...
    | catchments_raw.reference.str.startswith('YW')  # ... Yorkshire Water ...
    | catchments_raw.reference.str.startswith('WW')  # ... Welsh Water ...
)
catchments_raw = catchments_raw[~fltr]
print(f'dropped {fltr.sum()} treatment works not owned by Severn Trent Water')

# Backfill the name if only the ref is available and vice-versa.
catchments_raw.name.fillna(catchments_raw.reference, inplace=True)
catchments_raw.reference.fillna(catchments_raw.name, inplace=True)

# Buffer to make the shapes valid.
print(f'{100 * catchments_raw.is_valid.mean():.3f}% of catchments are valid')
catchments_raw['geometry'] = catchments_raw.geometry.buffer(0)

# Show the breakdown by company.
counts = catchments_raw.groupby('company').count()
print(counts.sum())
counts
```

```python
# Apply manual fixes to the data.
update = [
    [('thames_water', 'EAST HYDE STW'),
     {'comment': 'Overlap with the Chalton and Offley catchments from Anglian Water.'}],
    [('thames_water', 'NAGS HEAD LANE STW'),
     {'comment': 'Overlap with the (Shenfield and Hutton) and Upminster catchments from Anglian Water.'}],
    [('thames_water', 'BARKWAY STW'),
     {'comment': 'The catchment as substantial overlap with the Barley catchment from anglian_water.'}],
    [('anglian_water', 'Chalton'),
     {'comment': 'Overlap with the East Hyde catchment from Thames Water.'}],
    [('anglian_water', 'Shenfield And Hutton'),
     {'comment': 'Overlap with the Nags Head Lane catchment from Thames Water.'}],
    [('anglian_water', 'Buckminster'),
     {'comment': 'Overlap with the Waltham catchment from Severn Trent Water.'}],
    [('anglian_water', 'Barley'),
     {'comment': 'Overlap with the BARKWAY STW catchment from thames_water.'}],
    [('severn_trent_water', 'CLAY CROSS (WRW)'),
     {'comment': 'Overlap with the Danesmoor catchment from Yorkshire Water.'}],
    [('severn_trent_water', 'WALTHAM (WRW)'),
     {'comment': 'Overlap with the Buckminster catchment from Anglian Water.'}],
    [('severn_trent_water', 'ABBEY LATHE - MALTBY (WRW)'),
     {'comment': 'Overlap with the Aldwarke catchment from Yorkshire Water.'}],
    [('yorkshire_water', 'Danesmoor'),
     {'comment': 'Overlap with the Clay Cross catchment from Severn Trent Water.'}],
    [('yorkshire_water', 'Aldwarke'),
     {'comment': 'Overlap with the Abbey Lathe - Maltby catchment from Severn Trent Water.'}],
    [('severn_trent_water', 'WIGMORE (WRW)'),
     {'comment': 'Overlap with the The Orchards SPS catchment from welsh_water.'}],
    [('welsh_water', 'The Orchards SPS'),
     {'comment': 'Overlap with the WIGMORE (WRW) catchment from severn_trent_water.'}],
    [('united_utilities', 'UU-08-SC42-BROMB'),
     {'comment': 'Overlap with the NESTON catchment from welsh_water.'}],
    [('welsh_water', 'NESTON'),
     {'comment': 'Overlap with the UU-08-SC42-BROMB catchment from united_utilities.'}],
    [('severn_trent_water', 'SCARCLIFFE (WRW)'),
     {'comment': 'Overlap with the Bolsover catchment from yorkshire_water.'}],
    [('yorkshire_water', 'Bolsover'),
     {'comment': 'Overlap with the SCARCLIFFE (WRW) catchment from severn_trent_water.'}],
    [('severn_trent_water', 'CLOWNE (WRW)'),
     {'comment': 'Overlap with the Staveley catchment from yorkshire_water.'}],
    [('yorkshire_water', 'Staveley'),
     {'comment': 'Overlap with the CLOWNE (WRW) catchment from severn_trent_water.'}],
    [('southern_water', 'LONGFIELD'),
     {'comment': 'Overlap with the LONG REACH STW catchment from thames_water.'}],
    [('united_utilities', 'UU-05-SC26-COLNE'),
     {'comment': 'Overlap with the Foulridge catchment from yorkshire_water.'}],
    [('yorkshire_water', 'Foulridge'),
     {'comment': 'Overlap with the UU-05-SC26-COLNE catchment from united_utilities.'}],
    [('anglian_water', 'Offley'),
     {'comment': 'Overlap with the EAST HYDE STW catchment from thames_water.'}],
    [('thames_water', 'RIVERSIDE STW'),
     {'comment': 'Overlap with the Upminster catchment from anglian_water.'}],
    [('anglian_water', 'Upminster'),
     {'comment': 'Overlap with the RIVERSIDE STW and NAGS HEAD LANE STW catchments from thames_water.'}],
    [('southern_water', 'REDLYNCH'),
     {'comment': 'Overlap with the DOWNTON STW CATCHMENT catchment from wessex_water.'}],
    [('wessex_water', 'DOWNTON STW CATCHMENT'),
     {'comment': 'Overlap with the REDLYNCH catchment from southern_water.'}],
    [('severn_trent_water', 'COALEY (WRW)'),
     {'comment': 'Overlap with the NORTH NIBLEY STW CATCHMENT catchment from wessex_water.'}],
    [('wessex_water', 'NORTH NIBLEY STW CATCHMENT'),
     {'comment': 'Overlap with the COALEY (WRW) catchment from severn_trent_water.'}],
    [('united_utilities', 'UU-11-SC58-ELLES'),
     {'comment': 'Overlap with the CHESTER catchment from welsh_water.'}],
    [('welsh_water', 'CHESTER'),
     {'comment': 'Overlap with the UU-11-SC58-ELLES and UU-11-SC58-WAVER catchments from united_utilities.'}],
    [('severn_trent_water', 'LYDNEY (WRW)'),
     {'comment': 'Overlap with the NEWLAND catchment from welsh_water.'}],
    [('welsh_water', 'NEWLAND'),
     {'comment': 'Overlap with the LYDNEY (WRW) catchment from severn_trent_water.'}],
    [('thames_water', 'GUILDFORD STW'),
     {'comment': 'Overlap with the GUILDFORD catchment from southern_water.'}],
    [('southern_water', 'GUILDFORD'),
     {'comment': 'Overlap with the GUILDFORD STW catchment from thames_water.'}],
    [('severn_trent_water', 'STRONGFORD (WRW)'),
     {'comment': 'Overlap with the UU-11-SC59-MADEL and UU-11-SC60-KIDSG catchments from united_utilities.'}],
    [('united_utilities', 'UU-11-SC59-MADEL'),
     {'comment': 'Overlap with the STRONGFORD (WRW) catchment from severn_trent_water.'}],
    [('southern_water', 'PENNINGTON'),
     {'comment': 'Overlap with the CHRISTCHURCH STW CATCHMENT catchment from wessex_water.'}],
    [('wessex_water', 'CHRISTCHURCH STW CATCHMENT'),
     {'comment': 'Overlap with the PENNINGTON catchment from southern_water.'}],
    [('thames_water', 'LONG REACH STW'),
     {'comment': 'Overlap with the IDE HILL TO THAMES, LONG HILL TO THAMES, LONGFIELD, and NORTHFLEET catchments from southern_water.'}],
    [('southern_water', 'IDE HILL TO THAMES'),
     {'comment': 'Overlap with the LONG REACH STW catchment from thames_water.'}],
    [('united_utilities', 'UU-08-SC41-BIRKE'),
     {'comment': 'Overlap with the HESWALL catchment from welsh_water.'}],
    [('welsh_water', 'HESWALL'),
     {'comment': 'Overlap with the UU-08-SC41-BIRKE catchment from united_utilities.'}],
    [('severn_trent_water', 'BRANTON (WRW)'),
     {'comment': 'Overlap with the Sandall catchment from yorkshire_water.'}],
    [('yorkshire_water', 'Sandall'),
     {'comment': 'Overlap with the BRANTON (WRW) catchment from severn_trent_water.'}],
    [('united_utilities', 'UU-11-SC60-KIDSG'),
     {'comment': 'Overlap with the STRONGFORD (WRW) catchment from severn_trent_water.'}],
    [('united_utilities', 'UU-11-SC58-WAVER'),
     {'comment': 'Overlap with the CHESTER catchment from welsh_water.'}],
    [('severn_trent_water', 'DINNINGTON (WRW)'),
     {'comment': 'Overlap with the Woodhouse Mill catchment from yorkshire_water.'}],
    [('yorkshire_water', 'Woodhouse Mill'),
     {'comment': 'Overlap with the DINNINGTON (WRW) catchment from severn_trent_water.'}],
    [('southern_water', 'LONGFIELD HILL TO THAMES'),
     {'comment': 'Overlap with the LONG REACH STW catchment from thames_water.'}],
    [('southern_water', 'NORTHFLEET'),
     {'comment': 'Overlap with the LONG REACH STW catchment from thames_water.'}],
    [('northumbrian_water', 'GUISBOROUGH STW Holding Tanks? NZ60160101'),
     {'comment': 'Overlap with the MARSKE STW NZ62221701 catchment from yorkshire_water. These are only holding tanks.'}],
]

# Treatment works to remove because they are duplicates. We can check which is the correct company
# using https://www.water.org.uk/advice-for-customers/find-your-supplier/.
drop = {
    'northumbrian_water': [
        # Great Smeaton, DL6 2ET, supplied Yorkshire Water.
        'GREAT SMEATON STW NZ34043201',
        # Brampton, CA8 2Qg, United Utilities.
        'TINDALE STW NY61599206',
    ],
    'thames_water': [
        # Wingrave, HP22 4PS, supplied by Anglian Water.
        'WINGRAVE STW',
        # Stewkley, LU7 0EL, supplied by Anglian Water.
        'STEWKLEY STW',
        # RH12 4BB, supplied by Southern Water.
        'COLGATE STW',
        # Anglian.
        'DUNSTABLE (AW) STW',
    ],
    'united_utilities': [
        # Doveholes, SK17 8BL, supplied by Severn Trent.
        'UU-10-SC54-DOVEH',
        # Various catchments supplied by Severn Trent.
        'UU-11-SC59-SVNTR',
    ],
    'severn_trent_water': [
        # Acton Green, SWR6 5AA, supplied by Welsh Water.
        'ACTON GREEN (WRW)',
        # Severn Trent are missing Thealby and Normanby
        # (but the Anglian Water catchment is rather coarse).
        'BURTON STATHER (WRW)',
    ],
    'anglian_water': [
        # SG4 7AA, Thames Water.
        'Weston',
        # CM24 8BE, Thames Water.
        'Henham',
        # DN9 3ED, Severn Trent.
        'Ex Raf Finningley',
        # Charndon, Thames.
        'Chardon',
        # This is technically Anglian, but Thames have better data.
        # Specifically, Anglian are missing Marston St Lawrence.
        'Halse',
        # Severn Trent have better data. Anglian are missing Bothamsall.
        'Elkesley',
        # LE15 7PL, Severn Trent.
        'Market Overton',
        # The Severn Trent data is more refined and actually covers Alkborough.
        'Alkborough',
        # Covered by Thames Water.
        'Graveley',
    ],
    'welsh_water': [
        # SY12 9LD, Severn Trent Water.
        'DUDLESTON HEATH',
        # sy13 2af, Severn Trent.
        'ASH MAGNA',
    ],
    'southern_water': [
        # Thames Water provide the treatment in Crawley.
        'COPTHORNE',
        # Covered by Thames.
        'SMALLFIELD',
        'HASLEMERE',
        'GREENHYTHE',
    ],
    'south_west_water': [
        # Overlapping data from Wessex water seems more likely to be correct by manual
        # inspection because the treatment works at 50.863244779522724, -2.753987039083524
        # Likely serves both Mosterton and Chedington.
        'MOSTERTON_SPS_MOSTERTON',
    ]
}

catchments = catchments_raw.copy()

# Drop each catchment individually, ensuring that we drop exactly one per name/company.
for company, names in drop.items():
    for name in names:
        f = (catchments.name == name) & (catchments.company == company)
        assert f.sum() == 1, (company, name, f.sum())
        catchments = catchments[~f]
print(f'dropped {sum(len(names) for names in drop.values())} catchments')

# Update each record in turn, ensuring we only update exactly one per name/company(/reference).
for key, item in update:
    if len(key) == 2:
        (company, name) = key
        f = (catchments.name == name) \
            & (catchments.company == company)
    else:
        (company, name, reference) = key
        f = (catchments.name == name) \
            & (catchments.company == company) \
            & (catchments.reference == reference)
    assert f.sum() == 1, (company, name, f.sum())

    for key, value in item.items():
        catchments.loc[f, key] = value

print(f'updated {len(update)} catchments')

# Show the counts by company after updates.
counts = catchments.groupby('company').count()
print(counts.sum())
counts
```

```python
# Show an overview of the data we are now left with.
ax = catchments.plot(
    column='company',
    categorical=True,
    legend=True,
    legend_kwds={
        'fontsize': 'x-small',
        'ncol': 2,
    }
)
ax.ticklabel_format(scilimits=(0, 0), useMathText=True)
```

```python
# Get the intersections of catchments.
sindex = catchments.geometry.sindex
indices = sindex.query_bulk(catchments.geometry).T
print(f'found {len(indices)} intersections')

# Remove self-intersections and only report each intersection once.
indices = indices[indices[:, 0] < indices[:, 1]]
print(f'found {len(indices)} intersections without self intersections')

# Calculate the actual intersection areas and remove zero-area intersections.
i, j = indices.T
x = catchments.iloc[i].geometry.reset_index(drop=True)
y = catchments.iloc[j].geometry.reset_index(drop=True)
intersection_areas = x.intersection(y).area.values
intersection_threshold = 10
f = intersection_areas > intersection_threshold
intersection_areas = intersection_areas[f]
indices = indices[f]

print(f'found {len(indices)} intersections with intersection area > {intersection_threshold}')

# Evaluate the unions.
i, j = indices.T
x = catchments.iloc[i].geometry.reset_index(drop=True)
y = catchments.iloc[j].geometry.reset_index(drop=True)
union_areas = x.union(y).area.values
```

```python
# Create a data frame that has information about both pairs of an intersection as well as
# intersection information, such as the area.
parts = [catchments.iloc[i].copy().reset_index(drop=True), catchments.iloc[j].copy().reset_index(drop=True)]
for suffix, part in zip(['_x', '_y'], parts):
    part.columns = [col + suffix for col in part]
overlapping = gpd.GeoDataFrame(pd.concat(parts, axis=1))
overlapping['intersection_areas'] = intersection_areas
overlapping['union_areas'] = union_areas
overlapping['iou'] = overlapping.intersection_areas / overlapping.union_areas
overlapping = overlapping.sort_values('iou', ascending=False)

# Restrict to settings where the water companies that provided the data differ (e.g. to avoid self
# overlap within subcatchments).
f = (overlapping.company_y != overlapping.company_x)
print(f'{f.sum()} overlapping catchments from different companies')

# Filter out the pairs where one or more catchments have an annotation.
f &= (overlapping.comment_x.isnull() | overlapping.comment_y.isnull())
overlapping = overlapping.loc[f]

# Manual exclusion of items that have been investigated and considered insignificant.
ignore = [
    {
        'company_x': 'severn_trent_water',
        'name_x': 'private',
        'company_y': 'welsh_water',
        'name_y': 'LYDBROOK',
    }
]
for item in ignore:
    f = True
    for key, value in item.items():
        f = f & (overlapping[key] == value)
    overlapping = overlapping.loc[~f]

assert len(overlapping) == 0, f'{len(overlapping)} unaccounted overlaps found'
```

```python
# Show the breakdown of areas covered by each company in square kilometres.
areas = catchments.groupby('company').geometry.apply(lambda x: x.area.sum()) / 1e6
print(f'total area covered: {areas.sum()}')
areas.round()
```

```python
# Show an overview figure.
fig = plt.figure(figsize=(5.8, 5.8))
gs = fig.add_gridspec(2, 2, width_ratios=[3, 2])
ax3 = fig.add_subplot(gs[:, 0])
tolerance = 1000
countries = gpd.read_file('data/geoportal.statistics.gov.uk/countries20_BGC.zip')
countries.simplify(tolerance=tolerance).plot(
    ax=ax3, facecolor='none', edgecolor='k', lw=.5)
simplified = catchments.copy().sort_values("company")
simplified['geometry'] = simplified.simplify(tolerance=tolerance)

# Group the catchments by company and plot them. We could also use the `column`
# keyword argument, but that is non-trivial with the number of companies we have.
# This may not be the "best" approach, but it's simple.

colors_by_company = {}
for i, (company, subset) in enumerate(simplified.groupby("company")):
    color = f"C{i}" if i < 10 else "#7FB087"
    subset.boundary.plot(ax=ax3, zorder=9, lw=.5, color=color)
    colors_by_company[company] = color
ax3.set_ylim(top=1.43e6)

ax1 = fig.add_subplot(gs[0, 1])
ax2 = fig.add_subplot(gs[1, 1])

alpha = 0.5

# Easy to tell that they're duplicates.
colors = ['C0', 'C3']
subset = catchments_raw.loc[catchments_raw.name.str.lower().str.contains('market overton').fillna(False)]
subset.plot(ax=ax1, facecolor=colors, alpha=alpha, edgecolor='face')
handles = [mpl.patches.Rectangle((0, 0), 1, 1, color=color, alpha=alpha)
           for color in colors]

# Hard to tell what's going on.
colors = ['C5', 'C0']
subset = catchments_raw.loc[np.in1d(catchments_raw.name, ['EAST HYDE STW', 'Chalton'])]
subset.plot(ax=ax2, facecolor=colors, alpha=alpha, edgecolor='face')

for ax, label in zip([ax3, ax1, ax2], ['(a)', '(b)', '(c)']):
    ax.set_axis_off()
    ax.text(0.05, 0.05, label, transform=ax.transAxes)

handles_labels = [
    (
        mpl.lines.Line2D([], [], color=value, marker="o", ls="none"),
        key.replace('_', ' ').title().removesuffix(" Water"),
    )
    for key, value in colors_by_company.items()
]
fig.legend(*zip(*handles_labels), ncol=2, loc='upper left', frameon=False)

fig.tight_layout()
fig.savefig('overview.pdf')
```

```python
# Evaluate unique identifiers for the catchments based on the first ten characters of the sha1 hash
# of the geometry rounded to the nearest metre. Then save the file.
def hash_function(geometry):
    coords = geometry.envelope.exterior.coords
    return hashlib.sha1(np.round(coords)).hexdigest()[:10]

identifiers = catchments.geometry.apply(hash_function)
assert identifiers.nunique() == len(identifiers)

catchments['identifier'] = identifiers
catchments.to_file(
    'data/wastewater_catchment_areas_public/catchments_consolidated.shp',
    encoding="utf-8",
)
```

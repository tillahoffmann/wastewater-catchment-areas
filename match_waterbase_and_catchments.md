---
jupyter:
  jupytext:
    text_representation:
      extension: .md
      format_name: markdown
      format_version: '1.3'
      jupytext_version: 1.16.7
  kernelspec:
    display_name: Python 3 (ipykernel)
    language: python
    name: python3
---

```python
import fiona  # Needs to be imported first for geopandas to work.
import geopandas as gpd
import matplotlib as mpl
from matplotlib import pyplot as plt
import numpy as np
import pandas as pd
import pathlib
import re
from tqdm.notebook import tqdm

mpl.rcParams['figure.dpi'] = 144
mpl.style.use('scrartcl.mplstyle')

ROOT = pathlib.Path('data/wastewater_catchment_areas_public')
```

```python
catchments = gpd.read_file(ROOT / 'catchments_consolidated.shp')
catchments.head()
```

```python
# Load the waterbase data.
uwwtps = gpd.GeoDataFrame(pd.read_csv(ROOT / 'waterbase_consolidated.csv'))

# Identify the treatment plants that were inactive in the most recent report.
inactive = []
for uwwCode, subset in uwwtps.groupby('uwwCode'):
    subset = subset.sort_values('year')
    item = subset.iloc[-1]
    if item.uwwState == 'inactive':
        inactive.append(item)
inactive = pd.DataFrame(inactive)

# Drop treatment works that are inactive.
print(f'starting with {uwwtps.uwwCode.nunique()} treatment plants')
uwwtps = uwwtps.loc[~np.in1d(uwwtps.uwwCode, inactive.uwwCode)]
print(f'retained {uwwtps.uwwCode.nunique()} treatment plants after removing inactive plants')

# Drop all treatment works from Northern Ireland Water and and Gibraltar.
uwwtps = uwwtps[~(
    uwwtps.uwwCode.str.startswith('UKNI') |
    uwwtps.uwwCode.str.startswith('UKGIB')
)]

print(f'retained {uwwtps.uwwCode.nunique()} treatment plants after removing treatment plants owned '
      'by water companies that did not supply data')

# Ensure that all retained treatment plants have reported at least one record for capacity and load.
grouped = uwwtps.groupby('uwwCode')
np.testing.assert_array_less(1, grouped.uwwCapacity.max())
np.testing.assert_array_less(1, grouped.uwwLoadEnteringUWWTP.max())

# Reproject into the british national grid.
uwwtps['geometry'] = gpd.points_from_xy(uwwtps.uwwLongitude, uwwtps.uwwLatitude)
uwwtps = gpd.GeoDataFrame(uwwtps).set_crs('epsg:4326').to_crs('epsg:27700')

# Group by treatment code and take the most recent data.
uwwtps = uwwtps.sort_values('year').groupby('uwwCode').last().reset_index()
uwwtps.head()
```

```python
# Evaluate the distance matrix between catchments and treatment works.
distances = []
for _, catchment in tqdm(catchments.iterrows(), total=len(catchments)):
    distances.append(uwwtps.distance(catchment.geometry, align=False))
# Cast to a dataframe.
distances = np.asarray(distances)
distances = pd.DataFrame(distances, index=catchments.identifier, columns=uwwtps.uwwCode)
distances.shape
```

```python
# Sweep over different distance thresholds and evaluate how many entities are close to each other
# at that radius.
thresholds = np.logspace(1, 3, 50)
num_uwwtps_near_catchment = []
num_catchments_near_uwwtp = []
for threshold in thresholds:
    near = distances < threshold
    num_uwwtps_near_catchment.append(near.sum(axis=1))
    num_catchments_near_uwwtp.append(near.sum(axis=0))

num_uwwtps_near_catchment = np.asarray(num_uwwtps_near_catchment)
num_catchments_near_uwwtp = np.asarray(num_catchments_near_uwwtp)
assert num_uwwtps_near_catchment.shape == (len(thresholds), len(catchments))
assert num_catchments_near_uwwtp.shape == (len(thresholds), len(uwwtps))
```

```python
# Show the fraction of UWWTPs that have exactly one catchment within a distance given by the
# threshold. As expected, there is an optimal distance: small thresholds are too restrictive whereas
# large ones "confuse" different catchments.
fig, ax = plt.subplots()
fraction_single_catchment_near_uwwtp = np.mean(num_catchments_near_uwwtp == 1, axis=1)
line, = ax.plot(thresholds, fraction_single_catchment_near_uwwtp)
i = np.argmax(fraction_single_catchment_near_uwwtp)
ax.scatter(thresholds[i], fraction_single_catchment_near_uwwtp[i], color=line.get_color())
ax.set_xscale('log')
ax.set_xlabel('Thresholds (metres)')
ax.set_ylabel('Fraction of UWWTPs with unique\ncatchment @ threshold')
```

```python
# Find all combinations of catchments and treatment plants where both the treatment plant
# and the catchment are associated with exactly one other treatment plant/catchment at a given
# distance.
thresholds = np.linspace(0, 500, 50)
num = []
for threshold in tqdm(thresholds):
    binary = (distances <= threshold).values
    f = (binary.sum(axis=1) == 1)[:, None] & ((binary).sum(axis=0) == 1) & binary
    catchment_idx, stp_idx = np.nonzero(f)
    num.append(len(catchment_idx))

fig, ax = plt.subplots()
ax.plot(thresholds, num)
ax.set_xlabel('Thresholds (metres)')
ax.set_ylabel('# unique pairs @ threshold')
```

```python
# Step 1: distance-based matching.

# Find all combinations of catchments and treatment plants where both the treatment plant and the
# catchment are associated with exactly one other treatment plant/catchment below a given distance.
threshold = 100
binary = (distances <= threshold).values
f_distance = (binary.sum(axis=1) == 1)[:, None] & ((binary).sum(axis=0) == 1) & binary
print('distance matched', f_distance.sum())

# Validate uniqueness to ensure the logic is consistent.
np.testing.assert_array_less(f.sum(axis=0), 2)
np.testing.assert_array_less(f.sum(axis=1), 2)

def normalise_name(value):
    """
    Function to normalise treatment names by removing special characters and common abbreviations.
    """
    if pd.isnull(value):
        return value
    # Drop all special characters.
    value, _ = re.subn(r'[\(\)\[\]\{\}\.\&-]', '', value.lower())
    # Drop stw and wwtw (often suffixes).
    value, _ = re.subn(r'\b(stw|wwtw|doa|wrw|bucks)\b', '', value)
    # Drop all whitespace.
    value, _ = re.subn(r'\s', '', value)
    return value

# Step 2: name-based matching.

# Add all treatment works where the normalised names are identical and the distance is less than
# another threshold.
f_name = (catchments['name'].apply(normalise_name).values[:, None] == uwwtps.uwwName.apply(normalise_name).values) \
    & (distances.values <= 2500)

print('name matched', f_name.sum())

# Create the auto-matched lookup table.
catchment_idx, stp_idx = np.nonzero(f_distance | f_name)
auto_matched = pd.concat([
    uwwtps.iloc[stp_idx].reset_index(drop=True),
    catchments.iloc[catchment_idx].reset_index(drop=True).drop('geometry', axis=1)
], axis=1)[['identifier', 'name', 'uwwCode', 'uwwName']]
print('total automatically matched', auto_matched.uwwCode.nunique())
auto_matched.head()
```

```python
manual_matched = pd.DataFrame([
    ('214873b5cf', 'UU-09-SC47-DAVYH', 'UKENNW_UU_TP000042', 'Manchester and Salford (Davyhulme)STW'),
    ('d793a815d9', 'UU-10-SC50-ROYTO', 'UKENNW_UU_TP000105', 'ROYTON STW'),
    ('b65d2eebc7', 'UU-10-SC51-FAILS', 'UKENNW_UU_TP000048', 'FAILSWORTH STW'),
    ('bb6ca16304', 'UU-10-SC54-HAZEL', 'UKENNW_UU_TP000058', 'HAZEL GROVE STW'),
    ('59bd836fc3', 'UU-10-SC54-STOCK', 'UKENNW_UU_TP000116', 'STOCKPORT STW'),
    ('5900c96825', 'Shenfield and Hutton', 'UKENAN_AW_TP000230', 'SHENFIELD STW'),
    ('4647e75f9e', 'CARDIFF BAY', 'UKWAWA_WW_TP000026', 'CARDIFF STW'),
    # These two are the same treatment work.
    ('cd33d70a80', 'Catterick Village', 'UKENNE_YW_TP000007', 'CATTERICK STW'),
    ('cd33d70a80', 'Catterick Village', 'UKENNE_YW_TP000008', 'COLBURN STW'),
    ('27ec2163de', 'UU-11-SC56-NTHWI', 'UKENNW_UU_TP000097', 'NORTHWICH STW'),
    # Cuddington has been decommissioned and now feeds into Northwich, but it's all a bit tricky
    # because there can be pumping going on between the different treatment plants
    # (https://www.unitedutilities.com/about-us/cheshire/).
    (None, None, 'UKENNW_UU_TP000040', 'CUDDINGTON STW'),
    # Cotgrave feeds into Radcliffe.
    # https://www.nottinghamshire.gov.uk/planningsearch/DisplayImage.aspx?doc=cmVjb3JkX251bWJlcj02OTU4JmZpbGVuYW1lPVxcbnMwMS0wMDI5XGZpbGVkYXRhMiRcREIwMy0wMDMwXFNoYXJlZEFwcHNcRExHU1xQbGFuc1xQTEFOTklOR1xTY3ItMzY0OFxSYWRjbGlmZmUgRUlBIFNjcmVlbmluZyBPcGluaW9uIFJlcXVlc3QucGRmJmltYWdlX251bWJlcj01JmltYWdlX3R5cGU9cGxhbm5pbmcmbGFzdF9tb2RpZmllZF9mcm9tX2Rpc2s9MTIvMDQvMjAxNyAxMDozMzo0MQ==
    (None, None, 'UKENMI_ST_TP000064', 'COTGRAVE STW'),
    ('fb13da240a', 'MANSFIELD-BATH LANE (WRW)', 'UKENMI_ST_TP000143', 'MANSFIELD STW'),
    # https://goo.gl/maps/pFhJy3ZAxyABKwWc6
    ('9fcbac5ecc', 'STOKE BARDOLPH (WRW)', 'UKENMI_ST_TP000163', 'NOTTINGHAM STW'),
    ('7be11f772b', 'BEESTON -LILAC GROVE (WRW)', 'UKENMI_ST_TP000025', 'BEESTON STW'),
    ('c861b125a1', 'STRATFORD-MILCOTE (WRW)', 'UKENMI_ST_TP000206', 'STRATFORD  STW'),
    # Long Marston has been decommissioned.
    # https://waterprojectsonline.com/custom_case_study/pebworth-long-marston-stratford-upon-avon-transfer/
    (None, None, 'UKENMI_ST_TP000135', 'LONG MARSTON STW'),
    ('01bf76d616', 'MAPLE LODGE STW', 'UKENTH_TWU_TP000106', 'MAPLE LODGE, BUCKS STW"'),
    ('034de6cd3b', 'Eastwood', 'UKENNE_YW_TP000079', 'TODMORDEN   STW'),
    ('c64f685e8b', 'Neiley', 'UKENNE_YW_TP000109', 'HOLMFIRTH   STW'),
    ('7e5b0d4c85', 'UU-05-SC28-BLACK', 'UKENNW_UU_TP000018', 'BLACKBURN STW'),
    ('ccad6a0777', 'UU-05-SC28-DARWE', 'UKENNW_UU_TP000041', 'DARWEN STW'),
    ('31ec9a8fc2', 'UU-06-SC35-HUYTO', 'UKENNW_UU_TP000066', 'HUYTON STW'),
    ('a83266015d', 'UU-06-SC35-LIVER', 'UKENNW_UU_TP000080', 'LIVERPOOL SOUTH [WOOLTON]) STW'),
    ('0d2d457ce0', 'MARGATE AND BROADSTAIRS', 'UKENSO_SW_TP000019', 'BROADSTAIRS/MARGATE OUT CSM (Weatherlees B)'),
    ('bbd09a27de', 'WEATHERLEES HILL', 'UKENSO_SW_TP000022', 'RAMSGATE, SANDWICH, DEAL   STW"'),
    ('00e1c4c53b', 'UU-09-SC46-ECCLE', 'UKENNW_UU_TP000046', 'ECCLES STW'),
    ('feab30c503', 'UU-07-SC40-WORSL', 'UKENNW_UU_TP000140', 'WORSLEY STW'),
    ('a3aea16d4a', 'ABINGDON STW', 'UKENTH_TWU_TP000001', 'ABINGDON (OXON STW)'),
    ('b428837dda', 'NAGS HEAD LANE STW', 'UKENTH_TWU_TP000115', 'NAGS HEAD LANE ( BRENTWOOD STW'),
    ('3d27aa0af3', 'RIVERSIDE STW', 'UKENTH_TWU_TP000125', 'LONDON (Riverside STW)'),
    ('cee1fb4e33', 'UU-07-SC40-GLAZE', 'UKENNW_UU_TP000053', 'GLAZEBURY STW'),
    ('feec09aaaf', 'UU-07-SC40-LEIGH', 'UKENNW_UU_TP000078', 'LEIGH STW'),
    ('3b82554080', 'UU-07-SC39-BOLTO', 'UKENNW_UU_TP000019', 'BOLTON STW'),
    ('51bdbc0969', 'UU-07-SC37-BURYZ', 'UKENNW_UU_TP000026', 'BURY STW'),
    ('f08942bc5a', 'UU-10-SC52-ASHUL', 'UKENNW_UU_TP000007', 'ASHTON-UNDER-LYNE STW'),
    ('5d269b4c58', 'UU-10-SC52-DUKIN', 'UKENNW_UU_TP000044', 'DUKINFIELD STW'),
    ('b24ca82746', 'RHIWSAESON (NEW)', 'UKWAWA_WW_TP000024', 'RHIWSAESON STW RHIWSAESON LLANTRI STW'),
    ('a7ecedaef5', 'COSLECH', 'UKWAWA_WW_TP000020', 'SOUTH ELY VALLEY   STW'),
    ('2e2e1b5104', 'Dalscone DOA', 'UKSC_TP00053', 'DALSCONE S.T.W. (NEW)'),
    ('2e2e1b5104', 'Dalscone DOA', 'UKSC_TP00054', 'DALSCONE S.T.W.  (OLD)'),
    ('5f66794c55', 'Whilton', 'UKENAN_AW_TP000286', 'DAVENTRY   STW'),
    ('3b3e3efde8', 'BAKEWELL, PICKORY CORNER (WRW)', 'UKENMI_ST_TP000013', 'BAKEWELL STW'),
    ('2eb71ffcfc', 'BOTTESFORD-STW', 'UKENMI_ST_TP000033', 'BOTTESFORD STW'),
    ('e4a961fba1', 'KEMPSEY WORKS (WRW)', 'UKENMI_ST_TP000119', 'KEMPSEY STW'),
    ('53fe082858', 'CLAYMILLS (WRW)', 'UKENMI_ST_TP000056', 'BURTON ON TRENT   STW'),
    ('54e25cb6a9', 'MELTON (WRW)', 'UKENMI_ST_TP000152', 'MELTON MOWBRAY STW'),
    ('b0753764b4', 'STANLEY DOWNTON (WRW)', 'UKENMI_ST_TP000208', 'STROUD STW'),
    ('b11e60b850', 'ROUNDHILL (WRW)', 'UKENMI_ST_TP000180', 'STOURBRIDGE & HALESOWEN   STW'),
    ('ffe8483a02', 'ASH VALE STW', 'UKENTH_TWU_TP000009', 'ASH VALE, STRATFORD ROAD, NORTH STW"'),
    ('e526b8f3b6', 'BRACKNELL STW', 'UKENTH_TWU_TP000025', 'BRACKNELL, HAZELWOOD LANE, BINF STW"'),
    ('29d52395a3', 'UU-04-SC21-PREST', 'UKENNW_UU_TP000102', 'PRESTON (CLIFTON MARSH) STW'),
    ('c1e0195f63', 'WINDSOR STW', 'UKENTH_TWU_TP000152', 'WINDSOR, HAM ISLAND, OLD WINDSO STW"'),
    ('743841f528', 'CAMBERLEY STW', 'UKENTH_TWU_TP000033', 'CAMBERLEY, CAMBERLEY, SURREY STW"'),
    ('80c85e78c6', 'DORCHESTER STW', 'UKENTH_TWU_TP000056', 'DORCHESTER STW (OXON)'),
    ('0f5561c4b9', 'STANFORD RIVERS STW', 'UKENTH_TWU_TP000136', 'STANFORD RIVERS, ONGAR, ESSEX STW"'),
    ('45b2ebfd2f', 'UU-03-SC17-KRKLO', 'UKENNW_UU_TP000151', 'KIRKBY LONSDALE STW HUMUS TANK EFFLUENT'),
    ('935c2734be', 'MARLBOROUGH STW', 'UKENTH_TWU_TP000108', 'MARLBOROUGH, MARLBOROUGH, WILTS STW"'),
    ('ba3e9907f2', 'EARLSWOOD STW', 'UKENTH_TWU_TP000123', 'REIGATE STW'),
    ('98a14c9923', 'STANTON - DERBYSHIRE (WRW)', 'UKENMI_ST_TP000201', 'STANTON   STW'),
    ('1d9dcc765f', 'WORMINGHALL STW', 'UKENTH_TWU_TP000158', 'WORMINGHALL, WORMINGHALL, BUCKS STW"'),
    ('a087889829', 'SUTTON BONNINGTON (WRW)', 'UKENMI_ST_TP000278', 'SUTTON BONINGTON STW, FE"'),
    ('fd7e5039c1', 'STANSTED MOUNTFITCHET STW', 'UKENTH_TWU_TP000137', 'STANSTED MOUNTFITCHET, STANSTED STW"'),
    ('0d09ae579a', 'RAMSBURY STW', 'UKENTH_TWU_TP000121', 'RAMSBURY, RAMSBURY, MARLBOROUGH STW"'),
    ('0de7c65bea', 'UU-06-SC31-HSKBK', 'UKENNW_UU_TP000060', 'HESKETH BANK STW'),
    ('a8d4ccb494', 'CHICKENHALL EASTLEIGH', 'UKENSO_SW_TP000013', 'EASTLEIGH   STW'),
    ('0340b3c3c4', 'WALSALL WOOD (WRW)', 'UKENMI_ST_TP000221', 'WALSALL NORTH   STW'),
    ('47aebf7f1e', 'UU-03-SC18-LANCA', 'UKENNW_UU_TP000076', 'LANCASTER (STODDAY) STW'),
    ('95fa57e680', 'MILL GREEN STW', 'UKENTH_TWU_TP000111', 'MILL GREEN, HATFIELD, HERTS STW"'),
    ('f01161329e', 'SLOUGH STW', 'UKENTH_TWU_TP000133', 'SLOUGH, WOOD STW"'),
    ('d2e0ce618b', 'FINSTOCK STW', 'UKENTH_TWU_TP000067', 'FINSTOCK, FINSTOCK, OXON STW"'),
    ('15831f78a8', 'WOTTON UNDER EDGE STW CATCHMENT', 'UKENSW_WXW_TP000109', 'WOTTON UNDER EDGE STW'),
    ('8237f30715', 'STANFORD IN THE VALE STW', 'UKENTH_TWU_TP000169', 'Standford in the Vale STW'),
    ('a1e551a2fd', 'MORESTEAD ROAD WINCHESTER', 'UKENSO_SW_TP000003', 'WINCHESTER CENTRAL AND SOUTH (MORESTEAD) STW'),
    ('3b917f6c5f', 'BASINGSTOKE STW', 'UKENTH_TWU_TP000013', 'BASINGSTOKE, WILDMOOR, BASINGST STW"'),
    ('1903e1316b', 'FULLERTON', 'UKENSO_SW_TP000006', 'ANDOVER STW'),
    ('e9216a235f', 'Fochabers DOA', 'UKSC_TP00077', 'FOCHABERS WWTP'),
    ('965a041c6a', 'THAME STW', 'UKENTH_TWU_TP000140', 'THAME, THAME, OXON STW"'),
    ('c836b06a6e', 'GODALMING STW', 'UKENTH_TWU_TP000071', 'GODALMING, UNSTEAD, GODALMING, STW"'),
    ('bb40f7f215', 'UU-03-SC16-GRNGS', 'UKENNW_UU_TP000055', 'GRANGE-OVER-SANDS STW'),
    ('60cd9fef4c', 'DRENEWYDD - OSWESTRY (WRW)', 'UKENMI_ST_TP000166', 'OSWESTRY DRENEWYDD STW'),
    ('9edf9e05e3', 'HIGHER HEATH-PREES (WRW)', 'UKENMI_ST_TP000268', 'PREES HIGHER HEATH STW'),
    ('5b6ed3d068', 'RUSHMOOR (WRW)', 'UKENMI_ST_TP000184', 'TELFORD   STW'),
    ('d8b6f988ea', 'CHESHAM STW', 'UKENTH_TWU_TP000039', 'CHESHAM, BUCKS STW"'),
    ('04a2d621cd', 'UU-07-SC40-TYLDE', 'UKENNW_UU_TP000120', 'TYLDESLEY STW'),
    ('5353ff23aa', 'APPLETON STW', 'UKENTH_TWU_TP000006', 'APPLETON, ABINGDON, OXON STW"'),
    ('8fccf79af1', 'WHITE WALTHAM STW', 'UKENTH_TWU_TP000150', 'WHITE WALTHAM, WHITE WALTHAM, B STW"'),
    ('a2a6cca4f6', 'POWICK (WRW)', 'UKENMI_ST_TP000173', 'POWICK NEW STW'),
    ('c33bed15a5', 'Knostrop Merge High + Low', 'UKENNE_YW_TP000098', 'LEEDS (KNOSTROP) STW'),
    ('11d6a4c3d9', 'HAYDEN (WRW)', 'UKENMI_ST_TP000256', 'CHELTENHAM STW'),
    ('5b3b7769c8', 'Withernsea No. 2', 'UKENNE_YW_TP000139', 'WITHERNSEA OUTFALL STW'),
    ('864e5eaa8d', 'TRIMDON VILLAGE STW NZ37346301', 'UKENNE_NU_TP000052', 'TRIMDON VILLAGE STW'),
    ('d31b19b35b', 'NORTH TIDWORTH STW CATCHMENT', 'UKENSW_VE_TP000001', 'TIDWORTH GARRISON STW FE'),
    ('f00ad841f9', 'PEACEHAVEN', 'UKENSO_SW_TP000126', 'PEACEHAVEN WASTEWATER TREATMENT WKS'),
    # Morecambe is auto-matched to Middleton. But we also need the Morecambe catchment area itself.
    # (cf. page 3 of https://www.unitedutilities.com/globalassets/documents/pdf/7013b-morcambe-a5-6pp-flyer-v10_acc17.pdf).
    ('15d6d1fe75', 'UU-03-SC18-MOREC', 'UKENNW_UU_TP000092', 'MORECAMBE STW'),
    # South West Water
    ('86490b6f49', 'CULLOMPTON_STW_CULLOMPTON', 'UKENSW_SWS_TP000018', 'CULLOMPTON STW'),
    ('e0cef5009e', 'BRADNINCH_STW_BRADNINCH', 'UKENSW_SWS_TP000085', 'BRADNINCH STW'),
    ('9e49ba976b', 'WOODBURY_STW_WOODBURY', 'UKENSW_SWS_TP000083', 'WOODBURY STW'),
    ('85685023c6', 'SCARLETTS WELL_STW_BODMIN', 'UKENSW_SWS_TP000005', 'BODMIN (SCARLETTS WELL) STW'),
    ('8a6451d565', 'NANSTALLON_STW_BODMIN', 'UKENSW_SWS_TP000004', 'BODMIN (NANSTALLON) STW'),
    ('f67cadab83', 'COUNTESS WEAR_STW_EXETER', 'UKENSW_SWS_TP000023', 'EXETER STW'),
    # No good matches.
    (None, None, 'UKSC_TP00011', 'ANNANDALE WATER MSA S.T.W.'),
    (None, None, 'UKENTH_TWU_TP000162', 'ALDERSHOT MILITARY STW'),
    (None, None, 'UKSC_TP00201', 'FASLANE STW'),
    (None, None, 'UKSC_TP00085', 'GLENEAGLES STW'),
    (None, None, 'UKWAWA_WW_TP000128', 'BLUESTONE LEISURE CANASTON'),
    (None, None, 'UKENMI_ST_TP000227', 'WELSHPOOL STW'),
    (None, None, 'UKSC_TP00171', 'SOUTHERNESS STW'),
    (None, None, 'UKENMI_ST_TP000127', 'KNIGHTON STW'),
    (None, None, 'UKENMI_ST_TP000133', 'LLANIDLOES STW'),
    (None, None, 'UKENMI_ST_TP000161', 'NEWTOWN STW'),
    (None, None, 'UKWAWA_WW_TP000011', 'MERTHYR TYDFIL STW'),
], columns=['identifier', 'name', 'uwwCode', 'uwwName'])

matched = pd.concat([auto_matched, manual_matched])
unmatched = uwwtps[~uwwtps.uwwCode.isin(matched.uwwCode)]
unmatched
```

```python
# Ensure that the matching accounts for exactly the right set of treatment works.
assert set(matched.uwwCode) == set(uwwtps.uwwCode)
```

```python
# Make sure there are no invalid identifiers amongst the manual matches. That might happen
# if the underlying data change, e.g. as part of the request via whatdotheyknow.com.
invalid_identifiers = set(manual_matched.identifier) - set(catchments.identifier) - {None}
if invalid_identifiers:
    raise ValueError(f'found {len(invalid_identifiers)} invalid identifiers: {invalid_identifiers}')
```

```python
# Evaluate the distance between the catchment and the stp to give "a feel" for how good the matching
# is.
catchments_indexed = catchments.set_index('identifier')
uwwtps_indexed = uwwtps.set_index('uwwCode')
matched['distance'] = matched.apply(
    lambda x: None if pd.isnull(x.identifier) else
    catchments_indexed.geometry.loc[x.identifier].distance(uwwtps_indexed.geometry.loc[x.uwwCode]), axis=1)
matched.sort_values('uwwCode').to_csv(ROOT / 'waterbase_catchment_lookup.csv', index=False)
# Show the 99% distance between matched catchments and stps.
matched.distance.quantile([.5, .99])
```

```python
# Show catchments that are matched to more than one treatment work. This should NEVER happen, unless
# the same treatment work has been assigned different identifiers by UWWTD.

exceptions = [
    '2e2e1b5104',  # Dalscone New and Old.
    'a3aea16d4a',  # Abingdon appears twice.
    '8a5a88fe31',  # Balby appears twice.
    'd8270e9ad8',  # Catterick village and Colburn STWs are in the same location...
    'cd33d70a80',  # ... and the catchment needs to be linked to both treatment works.
]

counts = 0
for identifier, subset in matched.groupby('identifier'):
    if identifier in exceptions:
        continue
    if len(subset) > 1:
        print(subset)
        counts += 1

assert counts == 0, 'data doesn\'t make sense'
```

```python
# Show treatment works broken down by company.
counts = pd.merge(matched, catchments, on='identifier', how='left').groupby('company').uwwCode.nunique()
print('total number of treatment works', counts.sum())
counts
```

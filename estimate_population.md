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
import fiona
import geopandas as gpd
from matplotlib import pyplot as plt
import matplotlib as mpl
import numpy as np
import pandas as pd
import pathlib
import shapely
from scipy import stats
from tqdm.notebook import tqdm

mpl.rcParams['figure.dpi'] = 144
mpl.style.use('scrartcl.mplstyle')
```

```python
# Load all the data we need.
ROOT = pathlib.Path('data/wastewater_catchment_areas_public')

lsoas = gpd.read_file('data/geoportal.statistics.gov.uk/LSOA11_BGC.zip').set_index('LSOA11CD')

catchments = gpd.read_file(ROOT / 'catchments_consolidated.shp')

lsoa_catchment_lookup = pd.read_csv(ROOT / 'lsoa_catchment_lookup.csv')

lsoa_coverage = pd.read_csv(ROOT / 'lsoa_coverage.csv')

lsoa_population = pd.read_csv('data/ons.gov.uk/lsoa_syoa_all_years_t.csv',
                              usecols=['LSOA11CD', 'year', 'Pop_Total'])
lsoa_population['year'] = lsoa_population.year.apply(lambda x: int(x[4:]))

waterbase_catchment_lookup = pd.read_csv(ROOT / 'waterbase_catchment_lookup.csv')

waterbase_consolidated = pd.read_csv(ROOT / 'waterbase_consolidated.csv',
                                     index_col=['uwwCode', 'year'])
# Fix a data problem where someone dropped a zero (or another digit) for Kinmel Bay.
waterbase_consolidated.loc[('UKWAWA_WW_TP000093', 2016), 'uwwLoadEnteringUWWTP'] *= 10

# Add up the treated load for the two works in Abingdon (which should really just be one).
x = waterbase_consolidated.loc['UKENTH_TWU_TP000001'].uwwLoadEnteringUWWTP
y = waterbase_consolidated.loc['UKENTH_TWU_TP000165'].uwwLoadEnteringUWWTP
z = y.reindex(x.index).fillna(0) + x
waterbase_consolidated.loc['UKENTH_TWU_TP000001', 'uwwLoadEnteringUWWTP'] = z.values

# Get rid of the duplicate treatment work.
waterbase_consolidated = waterbase_consolidated.drop('UKENTH_TWU_TP000165', level=0)
waterbase_consolidated = waterbase_consolidated.reset_index()
```

```python
# Evaluate the total intersection area for each LSOA.
intersection_area_sum = lsoa_catchment_lookup.groupby('LSOA11CD')\
    .intersection_area.sum().reset_index(name='intersection_area_sum')

# Construct a data frame that has a number of different areas that we can use for normalisation.
merged = pd.merge(lsoa_coverage, intersection_area_sum, on='LSOA11CD')
merged = pd.merge(merged, lsoa_catchment_lookup, on='LSOA11CD')
merged = pd.merge(merged, lsoa_population, on='LSOA11CD')

def aggregate(subset):
    # Construct different normalisations.
    # - for total area, we divide by the area of the LSOA.
    # - for area covered, we divide by the area of the LSOA that's covered by *any* 
    #   catchment.
    # - for intersection sum, we divide by the sum of all intersections. This may be
    #   larger than the area of the catchments if the data has overlapping catchments.
    norms = {
        'norm_total_area': subset.total_area,
        'norm_area_covered': subset.area_covered,
        'norm_intersection_sum': subset.intersection_area_sum,
    }
    intersection_area_pop = subset.intersection_area * subset.Pop_Total
    return pd.Series({key: (intersection_area_pop / value).sum() for key, value in norms.items()})

grouped = merged.groupby(['identifier', 'year'])
geospatial_estimate = grouped.apply(aggregate)
geospatial_estimate.head()
```

```python
# Generate summary for table 1 of the publication.
year = 2016
method = "norm_intersection_sum"

summary = geospatial_estimate.reset_index()
summary = summary[summary.year == year]
summary = pd.merge(catchments, summary, on="identifier")
summary = summary.groupby("company").apply(
    lambda subset: {
        "population": subset[method].sum() / 1e6,
        "retained_catchments": len(subset),
        "area": np.round(subset.geometry.area.sum() / 1e6),
        "matched_uwwtp": subset.identifier.isin(waterbase_catchment_lookup.identifier).sum(),
    }
).apply(pd.Series) 

frac = (
    1e6 * summary.population.sum() 
    / lsoa_population[lsoa_population.year == year].Pop_Total.sum()
)
print(f"fraction covered: {frac}")
print(f"total covered: {summary.population.sum()}m")
summary
```

```python
# Merge the waterbase data (BOD p.e.) with geospatial population estimates for comparison.
merged = pd.merge(waterbase_catchment_lookup, waterbase_consolidated, on=['uwwCode', 'uwwName'])
merged = pd.merge(merged, geospatial_estimate, on=['year', 'identifier'])

# Sum by year and uwwCode (because the same treatment work may be linked to multiple catchments if
# the subcatchment aggregation didn't work out properly). Then assign back to the merged dataset and
# drop duplicates.
estimates = merged.groupby(['uwwCode', 'year']).agg({
    'norm_total_area': 'sum',
    'norm_area_covered': 'sum',
})
for key in estimates:
    merged[key] = [estimates.loc[(x.uwwCode, x.year), key] for _, x in merged.iterrows()]
merged = merged.drop_duplicates(['uwwCode', 'year'])

# Evaluate the pearson correlation on the log scale (omitting treatment works without load).
f = merged.uwwLoadEnteringUWWTP > 0
stats.pearsonr(np.log(merged.uwwLoadEnteringUWWTP[f]), np.log(merged[method][f]))
```

```python
# Show a figure of different population estimates for a given year.
fig = plt.figure()
gs = fig.add_gridspec(2, 2)
ax = fig.add_subplot(gs[:, 0])
year = 2016
subset = merged[merged.year == year]
ax.scatter(subset.uwwLoadEnteringUWWTP, subset[method], marker='.', alpha=.5)
ax.set_yscale('log')
ax.set_xscale('log')
lims = subset.uwwLoadEnteringUWWTP.quantile([0, 1])
ax.plot(lims, lims, color='k', ls=':')
ax.set_aspect('equal')
ax.set_xlabel('BOD person equivalent')
ax.set_ylabel('Geospatial population estimate')
ax.text(0.05, 0.95, '(a)', transform=ax.transAxes, va='top')

# Annotations.
annotations = [
    {
        'code': 'UKENNE_NU_TP000026',
        'label': 'Haggerston',
        'xfactor': 3,
        'yfactor': 1,
    },
    {
        'code': 'UKWAWA_WW_TP000016',
        'label': 'Rotherwas',
        'xfactor': 2.5,
    },
    {
        'code': 'UKENAN_AW_TP000020',
        'label': 'Billericay',
        'xfactor': 2/3,
        'yfactor': 3,
        'kwargs': {'ha': 'center'},
    },
    {
        'code': 'UKENAN_AW_TP000051',
        'label': 'Chalton',
        'xfactor': 1 / 3,
        'kwargs': {'ha': 'right'},
    },
]
indexed = subset.set_index('uwwCode')
for annotation in annotations:
    item = indexed.loc[annotation['code']]

    ax.annotate(
        annotation['label'],
        (item.uwwLoadEnteringUWWTP, item[method]),
        (item.uwwLoadEnteringUWWTP * annotation.get('xfactor', 1),
            item[method] * annotation.get('yfactor', 1)),
        arrowprops={
            'arrowstyle': '-|>',
        },
        va='center',
        **annotation.get('kwargs', {}),
    )
    print(annotation['label'], item.uwwName)

ax3 = ax = fig.add_subplot(gs[:, 1])
target = lambda x: np.median(np.abs(np.log10(x[method] / x.uwwLoadEnteringUWWTP)))

x = []
y = []
ys = []
for year, subset in tqdm(merged.groupby('year')):
    x.append(year)
    # Evaluate the statistic.
    y.append(target(subset))
    # Run a bootstrap sample.
    ys.append([target(subset.iloc[np.random.randint(len(subset), size=len(subset))])
               for _ in range(1000)])

ys = np.asarray(ys)
l, u = np.percentile(ys, [25, 75], axis=1)
ax.errorbar(x, y, (y - l, u - y), marker='.')
ax.ticklabel_format(scilimits=(0, 0), axis='y', useMathText=True)
ax.set_xlabel('Year')
ax.set_ylabel('Median absolute\n$\\log_{10}$ error')
ax.xaxis.set_ticks([2006, 2008, 2010, 2012, 2014, 2016])
plt.setp(ax.xaxis.get_ticklabels(), rotation=30, ha='right')
ax.text(0.95, 0.95, '(b)', transform=ax.transAxes, ha='right', va='top')

fig.tight_layout()
fig.savefig('figures/population-estimates.pdf')
fig.savefig('figures/population-estimates.png')

# Show the log10 median absolute error over time.
y
```

```python
# Plot to illustrate why we're using area covered.
fig, ax = plt.subplots()

xmin = 515000
xmax = 523000
ymin = 170000
ymax = 176000
box = shapely.geometry.box(xmin, ymin, xmax, ymax)

# Plot the catchments.
idx_catchment = catchments.sindex.query(box)
subset = catchments.iloc[idx_catchment].sort_values('name')
subset = subset[subset.intersection(box).area > 10]
colors = ['C0', 'C1', 'C2']
subset.intersection(box).plot(ax=ax, color=colors)

# Plot the LSOAs.
idx = lsoas.sindex.query(box)
lsoas.iloc[idx].plot(ax=ax, facecolor='none', edgecolor='k', alpha=.1)
lsoas.loc[['E01003817']].plot(ax=ax, facecolor=(.5, .5, .5, .25), edgecolor='k')

ax.set_xlim(xmin, xmax)
ax.set_ylim(ymin, ymax)
ax.set_axis_off()
handles = [mpl.patches.Rectangle((0, 0), 1, 1, color=color) for color in colors]
labels = subset.name.str.replace(' STW', '').str.title()
ax.legend(handles, labels)

fig.tight_layout()
fig.savefig('figures/estimation_method.pdf')
fig.savefig('figures/estimation_method.png')
```

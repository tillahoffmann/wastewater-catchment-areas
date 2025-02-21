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
from tqdm.notebook import tqdm
import pandas as pd
import pathlib
from matplotlib import pyplot as plt
import numpy as np
import networkx as nx
```

```python
ROOT = pathlib.Path('data/wastewater_catchment_areas_public')

catchments = gpd.read_file(ROOT / 'catchments_consolidated.shp').set_index('identifier')
print(f'loaded {len(catchments)} catchments')
catchments.head()

# Drop all scottish water catchments because there should not be overlap with LSOAs.
catchments = catchments[catchments.company != "scottish_water"]
print(f'retained {len(catchments)} after dropping Scottish Water')
```

```python
# Find non-trivial intersections between treatment works. That have not already been
# annotated.
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
intersection_threshold = 100
f = intersection_areas > intersection_threshold
intersection_areas = intersection_areas[f]
indices = indices[f]

# Sort to have largest intersection areas first.
intersection_areas = intersection_areas
indices = indices
identifiers = catchments.index.values[indices]
```

```python
# Construct an intersection graph and get connected compnents.
graph = nx.Graph()
graph.add_edges_from([(*edge, {"weight": area}) for edge, area in zip(identifiers, intersection_areas)])
components = list(sorted(
    nx.connected_components(graph),
    key=lambda nodes: sum(data["weight"] for *_, data in graph.edges(nodes, data=True)),
    reverse=True,
))
print(f"found {len(components)} connected components")
```

```python
catchments[catchments.index.isin(components[3])].plot(column="name", alpha=0.5)
```

```python
lsoas = gpd.read_file('data/geoportal.statistics.gov.uk/LSOA11_BGC.zip').set_index('LSOA11CD')
print(f'loaded {len(lsoas)} LSOAs')
lsoas.head()
```

```python
# Evaluate the intersection area between LSOAs and catchments.
catchment_idx, lsoa_idx = lsoas.sindex.query_bulk(catchments.geometry)
print(f'found {len(catchment_idx)} intersections between catchments and LSOAs')
print(f'{len(set(lsoa_idx))} of {len(lsoas)} LSOAs intersect at least one catchment (at the '
      'envelope level)')

# Evaluate the proper intersection areas (not just whether they intersect).
intersection_areas = [catchments.geometry.iloc[i].intersection(lsoas.geometry.iloc[j]).area
                      for i, j in tqdm(zip(catchment_idx, lsoa_idx), total=len(catchment_idx))]

# Package the intersection areas in a dataframe and only retain intersections with non-zero area.
intersections = pd.DataFrame({
    'identifier': catchments.index[catchment_idx],
    'LSOA11CD': lsoas.index[lsoa_idx],
    'intersection_area': intersection_areas,
})
intersections = intersections[intersections.intersection_area > 0]
print(f'retained {len(intersections)} intersections after removing zero areas')
intersections.head()
intersections.to_csv(ROOT / 'lsoa_catchment_lookup.csv', index=False)
```

```python
# Evaluate the fraction of each LSOA covered.
grouped = intersections.groupby("LSOA11CD")
frac_covered = grouped.intersection_area.sum() / lsoas.geometry.area

coverage = pd.DataFrame({
    "n_catchments": grouped.identifier.nunique(),
    "frac": frac_covered,
})

# Check that there is at most full coverage if there is only an
# intersection with one treatment work.
assert coverage[coverage.n_catchments == 1].frac.max() < 1 + 1e-9
coverage.loc[coverage.n_catchments == 1, "frac"] = np.minimum(
    1, coverage.frac[coverage.n_catchments == 1]
)
coverage = coverage[coverage.frac > 1 + 1e-6]
print(
    f"There are {len(coverage)} LSOAs with total "
    "intersections exceeding their own area."
)
plt.hist(coverage.frac)

# Find the catchments that give rise to the "over-coverage".
catchment_identifiers = intersections[
    intersections.LSOA11CD.isin(coverage.index)
].groupby("identifier").identifier.count()


catchment_identifiers
```

```python
coverage = {}
for lsoa_code, subset in tqdm(intersections.groupby('LSOA11CD')):
    # Get the union of all possible intersections.
    if len(subset) > 1:
        all_intersecting = catchments.loc[subset.identifier].unary_union
    else:
        identifier = subset.identifier.iloc[0]
        all_intersecting = catchments.geometry.loc[identifier]
    # Evaluate the intersection of the LSOA with any catchment by intersecting with the spatial
    # union of the catchments.
    intersection = all_intersecting.intersection(lsoas.geometry.loc[lsoa_code])
    coverage[lsoa_code] = intersection.area

coverage = pd.Series(coverage)

# Compute the coverage and fill with zeros where there are no intersections.
lsoas['area_covered'] = coverage
lsoas['area_covered'] = lsoas.area_covered.fillna(0)
lsoas['total_area'] = lsoas.area
lsoas[['total_area', 'area_covered']].to_csv(ROOT / 'lsoa_coverage.csv')
```

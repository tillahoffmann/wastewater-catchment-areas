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
import numpy as np
from matplotlib import pyplot as plt
import matplotlib as mpl
import pandas as pd
import pathlib
import chardet
mpl.rcParams['figure.dpi'] = 144
```

```python
# Filenames for each version because there's no consistent naming
# convention.
filenames = {
    1: 'T_UWWTPS.csv',
    2: 'T_UWWTPS.csv',
    3: 'T_UWWTPS.csv',
    4: 'T_UWWTPS.csv',
    5: 'T_UWWTPs.csv',
    6: 'dbo.VL_UWWTPS.csv',
    7: 'UWWTPS.csv',
    8: 'UWWTPS.csv',
}
reporting_period_filenames = {
    1: 'T_ReportPeriod.csv',
    2: 'T_ReportPeriod.csv',
    3: 'T_ReportPeriod.csv',
    4: 'T_ReportPeriod.csv',
    5: 'T_ReportPeriod.csv',
    6: 'dbo.VL_ReportPeriod.csv',
    7: 'ReportPeriod.csv',
    8: 'ReportPeriod.csv',
}
```

```python
# The column names we're interested in.
state_keys = ['UK', 'GB']
columns = ['uwwCode', 'uwwName', 'uwwCapacity', 'uwwLoadEnteringUWWTP', 
           'rptMStateKey', 'uwwLatitude', 'uwwLongitude', 'uwwState']

# Load the data and stuff it all into one data frame.
parts = []
for version, filename in filenames.items():
    try:
        folder = pathlib.Path(f'data/eea.europa.eu/waterbase_v{version}_csv')
        
        # Detect the encoding.
        path = folder / filename
        with open(path, 'rb') as fp:
            text = fp.read()
            encoding = chardet.detect(text)

        # Load the data and filter to the UK.
        part = pd.read_csv(path, usecols=columns, encoding=encoding.get('encoding'))
        part = part[np.in1d(part.rptMStateKey, state_keys)]
        # Store the version.
        part['version'] = version
        # Strip leading and trailing whitespace from names.
        part['uwwName'] = part.uwwName.str.strip()

        # Load information on the reporting period.
        report_period = pd.read_csv(folder / reporting_period_filenames[version])
        report_period = report_period.set_index('rptMStateKey').repReportedPeriod.to_dict()
        year, = [report_period[key] for key in state_keys if key in report_period]

        print(version, year, len(part))
        part['year'] = year
        # Store the data
        parts.append(part)
    except Exception as ex:
        raise RuntimeError(f'failed to process {path}') from ex
    
data = pd.concat(parts)
# Remove random characters (non-breaking space in latin-1 and a missing character.
data['uwwName'] = data.uwwName.str.replace('\xa0', ' ').str.replace('�', '')
# Recode the state (two different values).
# https://dd.eionet.europa.eu/dataelements/99468
# https://www.eea.europa.eu/data-and-maps/data/waterbase-uwwtd-urban-waste-water-treatment-directive-7
state_mapping = {
    0: 'inactive',
    1: 'active',
    2: 'temporary inactive',
    105: 'inactive',
    106: 'active',
}
data['uwwState'] = data.uwwState.apply(lambda x: state_mapping[x])
data.head()
```

```python
# Show the year number as a function of the version.
versions = data[['version', 'year']].drop_duplicates()
fig, ax = plt.subplots()
ax.plot(versions.version, versions.year, marker='o')
ax.set_xlabel('Version')
ax.set_ylabel('Year')
fig.tight_layout()
```

```python
# Check that all data are the same in versions 3 and 4.
versions = [3, 4]
subsets = [data[data.version == version]
               .drop('version', axis=1)
               .sort_values('uwwCode')
               .reset_index(drop=True)
           for version in versions]
x, y = subsets
fltr = ((x == y) | (x.isnull() & y.isnull())).all(axis=1)
assert all(fltr)

# Then drop version 3.
cleaned = data[data.version != 3].copy()

# Fix a data error for Davyhulme that's got an order of magnitude error because there's an extra 1 prefixed.
cleaned.loc[cleaned.uwwCode == 'UKENNW_UU_TP000042', 'uwwCapacity'] = np.minimum(
    1206250, cleaned.loc[cleaned.uwwCode == 'UKENNW_UU_TP000042', 'uwwCapacity']
)
```

```python
# Show number of data points over time.
counts = cleaned.groupby('year').count()
fig, ax = plt.subplots()
ax.plot(counts.index, counts.uwwCapacity, label='capacity')
ax.plot(counts.index, counts.uwwLoadEnteringUWWTP, label='load entering')
ax.legend()
ax.set_ylabel('Number of data points')
ax.set_xlabel(counts.index.name)
fig.tight_layout()
```

```python
# Show capacity and load for Mogden.
code = 'UKENTH_TWU_TP000113'
subset = cleaned[cleaned.uwwCode == code]
kwargs = {
    'marker': 'o',
    'alpha': 0.5,
}

fig, ax = plt.subplots()
ax.plot(subset.year, subset.uwwCapacity, label='capacity', **kwargs)
ax.plot(subset.year, subset.uwwLoadEnteringUWWTP, label='load entering', **kwargs)
ax.set_xlabel('version')
ax.set_ylabel('people equivalent')
ax.legend()
fig.tight_layout()
```

```python
# Save the data.
cleaned.to_csv('data/wastewater_catchment_areas_public/waterbase_consolidated.csv', index=False)
```

```python
# Show availability of treatmentworks over time.
capacityAvailability = cleaned.set_index(['uwwCode', 'year']).uwwCapacity.unstack()
loadAvailability = cleaned.set_index(['uwwCode', 'year']).uwwLoadEnteringUWWTP.unstack()
fig, (ax1, ax2) = plt.subplots(1, 2, sharex=True, sharey=True)
kwargs = {
    'aspect': 'auto',
}
idx = np.argsort(loadAvailability.isnull().sum(axis=1))
ax1.imshow(~capacityAvailability.isnull().values[idx], **kwargs)
ax2.imshow(~loadAvailability.isnull().values[idx], **kwargs)
ax1.set_title('Capacity availability')
ax2.set_title('Load availability')
loadAvailability.shape
```

```python
# Show the cumulative distribution function of treatment work capacities.
fig, ax = plt.subplots()
for key in ['uwwCapacity', 'uwwLoadEnteringUWWTP']:
    values = cleaned.groupby('uwwCode')[key].max().sort_values()
    ax.plot(values, (np.arange(len(values)) + 1) / len(values), label=key)
ax.set_xscale('log')
ax.legend()
fig.tight_layout()
```

```python
# Show the scatter of capacity and load coloured by year.
fig, (ax1, ax2) = plt.subplots(1, 2, gridspec_kw={'width_ratios': [3, 2]})
ax = ax1
fltr = (cleaned.uwwCapacity > 0) & (cleaned.uwwLoadEnteringUWWTP > 0)
subset = cleaned[fltr]
mm = subset.uwwCapacity.min(), subset.uwwCapacity.max()
ax.scatter(subset.uwwCapacity, subset.uwwLoadEnteringUWWTP, c=subset.year, marker='.')
ax.plot(mm, mm, color='k', ls=':')
ax.set_yscale('log')
ax.set_xscale('log')
ax.set_aspect('equal')
ax.set_xlabel('Capacity')
ax.set_ylabel('Load entering')

above_capacity = cleaned.groupby('year').apply(lambda x: (x.uwwLoadEnteringUWWTP > x.uwwCapacity).mean())
above_or_at_capacity = cleaned.groupby('year').apply(lambda x: (x.uwwLoadEnteringUWWTP >= x.uwwCapacity).mean())
ax = ax2
ax.plot(above_capacity.index, above_capacity, marker='.', label='above capacity')
ax.plot(above_or_at_capacity.index, above_or_at_capacity, marker='.', label='above or at capacity')
ax.set_ylabel('Fraction of treatment works')
ax.set_xlabel('Year')
ax.set_yscale('log')
fig.tight_layout()
```

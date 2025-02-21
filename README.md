# Wastewater Catchment Areas in Great Britain

This repository provides code to consolidate wastewater catchment areas in Great Britain and evaluate their spatial overlap with statistical reporting units, such as Lower Layer Super Output Areas (LSOAs). Please see the [accompanying publication](https://doi.org/10.1002/essoar.10510612.2) for a detailed description of the analysis. If you have questions about the analysis, code, or accessing the data, please [create a new issue](https://github.com/tillahoffmann/wastewater-catchment-areas/issues/new).

## 🏁 Just give me the dataset

If you are interested in the consolidated dataset of wastewater catchment areas rather than reproducing the analysis, you can download it [here](https://gist.githubusercontent.com/tillahoffmann/fc12349c02950e43a9edefe5907eb62c/raw/catchments_consolidated.zip) ([Shapefile](https://en.wikipedia.org/wiki/Shapefile) format). More comprehensive results, including the CSV files described below, can be found [here](https://gist.githubusercontent.com/tillahoffmann/fc12349c02950e43a9edefe5907eb62c).

## 💾 Data

We obtained wastewater catchment area data from sewerage service providers under [Environmental Information Regulations 2004](https://en.wikipedia.org/wiki/Environmental_Information_Regulations_2004). We consolidated these geospatial data and matched catchments to wastewater treatment works data collected under the [Urban Wastewater Treatment Directive of the European Union](https://uwwtd.eu/United-Kingdom/). After analysis, the data comprise

- `catchments_consolidated.*`: geospatial data as a shapefile in the [British National Grid projection](https://epsg.io/7405), including auxiliary files. Each feature has the following attributes:

  - `identifier`: a unique identifier for the catchment based on its geometry. These identifiers are stable across different versions of the data provided the geometry of the associated catchment remains unchanged.
  - `company`: the water company that contributed the feature.
  - `name`: the name of the catchment as provided by the water company.
  - `comment` (optional): an annotation providing additional information about the catchment, e.g. overlaps with other catchments.
- `waterbase_consolidated.csv`: wastewater treatment plant metadata reported under the UWWTD between 2006 and 2018. See [here](https://www.eea.europa.eu/data-and-maps/data/waterbase-uwwtd-urban-waste-water-treatment-directive-7) for the original data. The columns comprise:

  - `uwwState`: whether the treatment work is `active` or `inactive`.
  - `rptMStateKey`: key of the member state (should be `UK` or `GB` for all entries).
  - `uwwCode`: unique treatment works identifier in the UWWTD database.
  - `uwwName`: name of the treatment works.
  - `uwwLatitude` and `uwwLongitude`: GPS coordinates of the treatment works in degrees.
  - `uwwLoadEnteringUWWTP`: actual load entering the treatment works measured in BOD person equivalents, corresponding to an "organic biodegradable load having a five-day biochemical oxygen demand (BOD5) of 60 g of oxygen per day".
  - `uwwCapacity`: potential treatment capacity measured in BOD person equivalents.
  - `version`: the reporting version (incremented with each reporting cycling, corresponding to two years).
  - `year`: the reporting year.

  Note that there are some data quality issues, e.g. treatment works `UKENNE_YW_TP000055` and `UKENNE_YW_TP000067` are both named `Doncaster (Bentley)` in 2006.

- `waterbase_catchment_lookup.csv`: lookup table to walk between catchments and treatment works. The columns comprise:

  - `identifier` and `name`: catchment identifier and name as used in `catchments_consolidated.*`.
  - `uwwCode` and `uwwName`: treatment works identifier and name as used in `waterbase_consolidated.csv`.
  - `distance`: distance between the catchment and treatment works in British National Grid projection (approximately metres).

- `lsoa_catchment_lookup.csv`: lookup table to walk between catchments and Lower Layer Super Output Areas (LSOAs). The columns comprise:

  - `identifier`: catchment identifier as used in `catchments_consolidated.*`.
  - `LSOA11CD`: LSOA identifier as used in the 2011 census.
  - `intersection_area`: area of the intersection between the catchment and LSOA in British National Grid projection (approximately square metres).

### Environmental Information Requests

Details of the submitted Environmental Information Requests can be found here:

- 🟢 [Anglian Water](https://www.whatdotheyknow.com/r/615f2df6-b1b3-42db-a236-8b311789a468): data provided and publicly accessible.
- 🔴 [Northern Ireland Water](https://www.whatdotheyknow.com/r/2b144b5d-abe6-4ad9-a61b-4e39f1e96e9f): request refused.
- 🟢 [Northumbrian Water](https://www.whatdotheyknow.com/r/aad55c04-bbc4-47a9-bec8-ea7e2a97f6d3): data provided and publicly accessible.
- 🟢 [Scottish Water](https://www.whatdotheyknow.com/r/0998addc-63f7-4a78-ac75-17fcf9b54b7d): data provided and publicly accessible.
- 🟢 [Severn Trent Water](https://www.whatdotheyknow.com/request/wastewater_catchment_areas): data provided and publicly accessible.
- 🟢 [Southern Water](https://www.whatdotheyknow.com/r/4cde4e22-1df0-42c8-b1a2-02e2cbd45b1b): data provided and publicly accessible.
- 🟢 [South West Water](https://www.whatdotheyknow.com/request/catchment_geospatial_data_files): data provided and publicly accessible.
- 🟢 [Thames Water](https://www.whatdotheyknow.com/r/e5915cbb-dc3b-4797-bf75-fe7cd8eb75c0): data provided and publicly accessible.
- 🟢 [United Utilities](https://www.whatdotheyknow.com/r/578035f9-a422-4c1b-a803-c257bf4f3414): data provided and publicly accessible.
- 🟢 [Welsh Water](https://www.whatdotheyknow.com/r/f482d33f-e753-45b2-9518-45ddf92fa718): data provided and publicly accessible.
- 🟢 [Wessex Water](https://www.whatdotheyknow.com/r/bda33cfd-e23d-49e6-b651-4ff8997c83c3): data provided and publicly accessible.
- 🟢 [Yorkshire Water](https://www.whatdotheyknow.com/r/639740ed-b0a3-4609-b4b6-a30a052fe037): data provided and publicly accessible.

You can use the following template to request the raw data directly from water companies.

> Dear EIR Team,
>
> Could you please provide the geospatial extent of wastewater catchment areas served by wastewater treatment plants owned or operated by your company as an attachment in response to this request? Could you please provide these data at the highest spatial resolution available in a machine-readable vector format (see below for a non-exhaustive list of suitable formats)? Catchment areas served by different treatment plants should be distinguishable.
>
> For example, geospatial data could be provided as shapefile (https://en.wikipedia.org/wiki/Shapefile), GeoJSON (https://en.wikipedia.org/wiki/GeoJSON), or GeoPackage (https://en.wikipedia.org/wiki/GeoPackage) formats. Other commonly used geospatial file formats may also be suitable, but rasterised file formats are not suitable.
>
> This request was previously submitted directly to the EIR team, and I trust I will receive the same response via the whatdotheyknow.com platform. Thank you for your time and I look forward to hearing from you.
>
> All the best,
> [your name here]

## 🔎 Reproducing the Analysis

1. Install [GDAL](https://gdal.org), e.g., on a Mac with [`brew`](https://brew.sh>) installed,

```bash
$ brew install gdal
```

2. Set up a clean python environment (this code has only been tested using python 3.9 on an Apple Silicon Macbook Pro), ideally using a virtual environment. Then install the required dependencies by running

```bash
$ pip install -r requirements.txt
```

3. Download the data (including data on Lower Layer Super Output Areas (LSOAs) and population in LSOAs from the ONS, Urban Wastewater Treatment Directive Data from the European Environment Agency, and wastewater catchment area data from whatdotheyknow.com) by running the following command.

```bash
$ make data
```

5. Validate all the data are in place and that you have the correct input data by running

```bash
$ make data/validation
```

6. Run the analysis by executing

```bash
$ make analysis
```

The last command will execute the following notebooks in sequence and generate both the data products listed above as well as the figures in the accompanying manuscript. The analysis will take between 15 and 30 minutes depending on your computer.

1. `consolidate_waterbase.ipynb`: load the UWWTD data, extract all treatment work information, and write the `waterbase_consolidated.csv` file.
2. `conslidate_catchments.ipynb`: load all catchments, remove duplicates, annotate, and write the `catchments_consolidated.*` files.
3. `match_waterbase_and_catchments.ipynb`: match UWWTD treatment works to catchments based on distances, names, and manual review. Writes the `waterbase_catchment_lookup.csv` file.
4. `match_catchments_and_lsoas.ipynb`: match catchments to LSOAs to evaluate their spatial overlap. Writes the files `lsoa_catchment_lookup.csv` and `lsoa_coverage.csv`.
5. `estimate_population.ipynb`: estimate the population resident within catchments, and write the `geospatial_population_estimates.csv` file.

## Acknowledgements

This research is part of the Data and Connectivity National Core Study, led by Health Data Research UK in partnership with the Office for National Statistics and funded by UK Research and Innovation (grant ref MC_PC_20029).

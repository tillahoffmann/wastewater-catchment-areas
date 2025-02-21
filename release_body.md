> [!IMPORTANT]
> The copyright of wastewater catchment area data rests with each sewerage service provider. Data were obtained through requests under the [Environmental Information Regulations 2004](https://en.wikipedia.org/wiki/Environmental_Information_Regulations_2004), and they are publicly available on whatdotheyknow.com (see the README section on [Environmental Information Requests](https://github.com/tillahoffmann/wastewater-catchment-areas?tab=readme-ov-file#environmental-information-requests) for further details). The MIT license only applies to the source code in this repository, not the data.
>
> The authors make no warranty on the correctness or completeness of the data.

This release includes the following files.

- `catchments_consolidated.zip`: Archive of consolidated wastewater catchment areas in [Shapefile](https://en.wikipedia.org/wiki/Shapefile) format. The properties for each catchment are:
  - `identifier`: Unique identifier for the catchment based on its geometry. These identifiers are stable across different versions of the data provided the geometry of the associated catchment remains unchanged.
  - `company`: Company that contributed the feature.
  - `name`: Name of the catchment as provided by the water company.
  - `comment` (optional): Annotation providing additional information about the catchment, e.g. overlaps with other catchments.

- `lsoa_catchment_lookup.csv`: Lookup table for intersections between Lower Layer Super Output Areas (LSOAs) and catchments. Columns are:
  - `identifier`: Unique identifier for the catchment based on its geometry, matching the identifier in `catchments_consolidated.zip`.
  - `LSOA11CD`: LSOA identifier.
  - `intersection_area`: Intersection area in [British National Grid](https://en.wikipedia.org/wiki/Ordnance_Survey_National_Grid) projection (approximately square metres). Aggregating the `intersection_area` by `LSOA11CD` may exceed the area of the LSOA itself if there are overlapping catchments.

- `lsoa_coverage.csv`: Coverage of each LSOA. Columns are:
  - `LSOA11CD`: LSOA identifier.
  - `total_area`: Area of the LSOA in British National Grid projection.
  - `area_covered`: Area of the LSOA in British National Grid projection that is covered by *any* catchment. `area_covered` is no larger than `total_area`.

- `waterbase_consolidated.csv`: Consolidated metadata for treatment plants collected under the Urban Wastewater Treatment Directive of the European Commission. The data are restricted to treatment plants in the United Kingdom. The properties for each plant are:
  - `uwwState`: State of the plant (`active` or `inactive`).
  - `rptMStateKey`: Member state key (`UK` or `GB`).
  - `uwwCode`: Unique plant identifier.
  - `uwwName`: Plant name.
  - `uwwLatitude` and `uwwLongitude`: Location of the plant.
  - `uwwLoadEnteringUWWTP`: Load in population equivalent.
  - `uwwCapacity`: Capacity in population equivalent.
  - `version`: Dataset version (corresponds to reporting year).
  - `year`: Reporting year.

- `waterbase_catchment_lookup.csv`: Lookup table for catchments and treatment plants. Columns are:
  - `identifier`: Unique identifier for the catchment based on its geometry, matching the identifier in `catchments_consolidated.zip`.
  - `name`: Name of the catchment, matching the name in `catchments_consolidated.zip`.
  - `uwwCode`: Unique identifier of the associated plant, matching the identifier in `waterbase_consolidated.csv`.
  - `uwwName`: Name of the associated plant, matching the name in `waterbase_consolidated.csv`.

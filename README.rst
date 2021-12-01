🧭 geomapping
=============

This repository provides code to consolidate wastewater catchment areas and evaluate their spatial overlap with statistical reporting units, such as Lower Layer Super Output Areas (LSOAs). If you are interested in the data products only, please see the following section. Please see the :ref:`Reproducing the Analysis` section for further details.

Data
----

Wastewater catchment area data were obtained from sewerage service providers under `Environmental Information Regulations 2004 <https://www.legislation.gov.uk/uksi/2004/3391/contents/made>`__. These geospatial data were consolidated and matched to wastewater treatment works data collected under the `Urban Wastewater Treatment Directive of the European Union <https://uwwtd.eu/United-Kingdom/>`__. The data can be accessed `here <https://drive.google.com/drive/folders/1WYhmVkng8YFDk2NPReFl5sqFY96sJ70X?usp=sharing>`__ and comprise:

- :code:`catchments_consolidated.*`: geospatial data as a shapefile in the `British National Grid projection <https://epsg.io/7405>`__, including auxiliary files. Each feature has the following attributes:

  - :code:`identifier`: a unique identifier for the catchment based on its geometry. These identifiers are stable across different versions of the data provided the geometry of the associated catchment remains unchanged.
  - :code:`company`: the water company that contributed the feature.
  - :code:`name`: the name of the catchment as provided by the water company.
  - :code:`comment` (optional): an annotation providing additional information about the catchment, e.g. overlaps with other catchments.
- :code:`waterbase_consolidated.csv`: wastewater treatment plant metadata reported under the UWWTD between 2006 and 2018. See `here <https://www.eea.europa.eu/data-and-maps/data/waterbase-uwwtd-urban-waste-water-treatment-directive-7>`__ for the original data. The columns comprise:

  - :code:`uwwState`: whether the treatment work is :code:`active` or :code:`inactive`.
  - :code:`rptMStateKey`: key of the member state (should be :code:`UK` or :code:`GB` for all entries).
  - :code:`uwwCode`: unique treatment works identifier in the UWWTD database.
  - :code:`uwwName`: name of the treatment works.
  - :code:`uwwLatitude` and :code:`uwwLongitude`: GPS coordinates of the treatment works in degrees.
  - :code:`uwwLoadEnteringUWWTP`: actual load entering the treatment works measured in BOD person equivalents, corresponding to an "organic biodegradable load having a five-day biochemical oxygen demand (BOD5) of 60 g of oxygen per day".
  - :code:`uwwCapacity`: potential treatment capacity measured in BOD person equivalents.
  - :code:`version`: the reporting version (incremented with each reporting cycling, corresponding to two years).
  - :code:`year`: the reporting year.

  Note that there are some data quality issues, e.g. treatment works :code:`UKENNE_YW_TP000055` and :code:`UKENNE_YW_TP000067` are both named :code:`Doncaster (Bentley)` in 2006.

- :code:`waterbase_catchment_lookup.csv`: lookup table to walk between catchments and treatment works. The columns comprise:

  - :code:`identifier` and :code:`name`: catchment identifier and name as used in `catchments_consolidated.*`.
  - :code:`uwwCode` and :code:`uwwName`: treatment works identifier and name as used in :code:`waterbase_consolidated.csv`.
  - :code:`distance`: distance between the catchment and treatment works in British National Grid projection (approximately metres).

- :code:`lsoa_catchment_lookup.csv`: lookup table to walk between catchments and Lower Layer Super Output Areas (LSOAs). The columns comprise:

  - :code:`identifier`: catchment identifier as used in `catchments_consolidated.*`.
  - :code:`LSOA11CD`: LSOA identifier as used in the 2011 census.
  - :code:`intersection_area`: area of the intersection between the catchment and LSOA in British National Grid projection (approximately square metres).

.. _Reproducing the Analysis:

Reproducing the Analysis
------------------------

1. Request the underlying data by emailing till dot hoffmann at oxon dot org, and extract the archive to :code:`data/eir`.
2. Set up a clean python environment (this code has only been tested using python 3.9 on an Apple Silicone Macbook Pro), ideally using a virtual environment. Then install the required dependencies by running.

   .. code:: bash

      pip install -r requirements.txt

3. Download auxiliary data, e.g. LSOA boundaries and UWWTD data, by running

   .. code:: bash

      make data

4. Run the analysis by executing

   .. code:: bash

      make analysis

The last command will execute the following notebooks in sequence and generate both the data products listed above as well as the figures in the accompanying manuscript.

1. :code:`consolidate_waterbase.ipynb`: load the UWWTD data, extract all treatment work information, and write the :code:`waterbase_consolidated.csv` file.
2. :code:`conslidate_catchments.ipynb`: load all catchments, remove duplicates, annotate, and write the :code:`catchments_consolidated.*` files.
3. :code:`match_waterbase_and_catchments.ipynb`: match UWWTD treatment works to catchments based on distances, names, and manual review. Writes the :code:`waterbase_catchment_lookup.csv` file.
4. :code:`match_catchments_and_lsoas.ipynb`: match catchments to LSOAs to evaluate their spatial overlap. Writes the files :code:`lsoa_catchment_lookup.csv` and :code:`lsoa_coverage.csv`.


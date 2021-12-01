.PHONY : clear_output data data/geoportal.statistics.gov.uk data/ons.gov.uk data/eea.europa.eu docs

NBEXECUTE = jupyter nbconvert --execute --output-dir=workspace --to=html
OUTPUT_ROOT = data/wastewater_catchment_areas_public

requirements.txt : requirements.in
	pip-compile -v

sync : requirements.txt
	pip-sync

docs :
	sphinx-build . docs/_build

clear_output :
	jupyter nbconvert --clear-output *.ipynb

# Getting the data =================================================================================

data : data/geoportal.statistics.gov.uk data/eea.europa.eu

# --------------------------------------------------------------------------------------------------

data/geoportal.statistics.gov.uk : \
	data/geoportal.statistics.gov.uk/LSOA11_BGC.zip \
	data/geoportal.statistics.gov.uk/countries20_BGC.zip

# Generalised LSOA boundaries clipped to the coastline
# https://geoportal.statistics.gov.uk/datasets/ons::lower-layer-super-output-areas-december-2011-boundaries-generalised-clipped-bgc-ew-v3/about
data/geoportal.statistics.gov.uk/LSOA11_BGC.zip :
	mkdir -p $(dir $@)
	curl -L -o $@ 'https://opendata.arcgis.com/api/v3/datasets/8bbadffa6ddc493a94078c195a1e293b_0/downloads/data?format=shp&spatialRefId=27700'

# Generalised countries clipped to the coastline
# https://geoportal.statistics.gov.uk/datasets/ons::countries-december-2020-uk-bgc/about
data/geoportal.statistics.gov.uk/countries20_BGC.zip :
	mkdir -p $(dir $@)
	curl -L -o $@ 'https://opendata.arcgis.com/api/v3/datasets/ad26732b081049d797620753db953185_0/downloads/data?format=shp&spatialRefId=27700'

# --------------------------------------------------------------------------------------------------

data/ons.gov.uk : data/ons.gov.uk/lsoa_syoa_all_years_t.csv

# Small area population estimates from 2001 to 2017
# https://www.ons.gov.uk/peoplepopulationandcommunity/populationandmigration/populationestimates/adhocs/009983populationestimatesforlowerlayersuperoutputareaslsoainenglandandwalessingleyearofageandsexmid2001tomid2017

data/ons.gov.uk/lsoa_syoa_all_years_t.csv :
	mkdir -p $(dir $@)
	curl -L -o $(dir $@)/lsoasyoaallyearst.zip \
		'https://www.ons.gov.uk/file?uri=/peoplepopulationandcommunity/populationandmigration/populationestimates/adhocs/009983populationestimatesforlowerlayersuperoutputareaslsoainenglandandwalessingleyearofageandsexmid2001tomid2017/lsoasyoaallyearst.zip'
	unzip -d $(dir $@) $(dir $@)/lsoasyoaallyearst.zip

# --------------------------------------------------------------------------------------------------

data/eea.europa.eu :
	python download_waterbase.py

# Processing of data ===============================================================================

analysis : workspace/consolidate_waterbase.html \
	workspace/consolidate_catchments.html \
	workspace/match_waterbase_and_catchments.html

workspace/consolidate_waterbase.html ${OUTPUT_ROOT}/waterbase_consolidated.csv \
		 : consolidate_waterbase.ipynb
	${NBEXECUTE} $<

workspace/consolidate_catchments.html ${OUTPUT_ROOT}/catchments_consolidated.shp overview.pdf \
		: consolidate_catchments.ipynb
	${NBEXECUTE} $<

workspace/match_waterbase_and_catchments.html ${OUTPUT_ROOT}/waterbase_catchment_lookup.csv \
		: match_waterbase_and_catchments.ipynb ${OUTPUT_ROOT}/catchments_consolidated.shp \
		${OUTPUT_ROOT}/waterbase_consolidated.csv
	${NBEXECUTE} $<

workspace/match_catchments_and_lsoas.html ${OUTPUT_ROOT}/lsoa_coverage.csv \
	${OUTPUT_ROOT}/lsoa_catchment_lookup.csv \
		: match_catchments_and_lsoas.ipynb ${OUTPUT_ROOT}/catchments_consolidated.shp
	${NBEXECUTE} $<

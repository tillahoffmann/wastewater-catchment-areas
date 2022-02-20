.PHONY : clear_output data data/geoportal.statistics.gov.uk data/ons.gov.uk data/eea.europa.eu docs \
	data/raw_catchments data/validation data.shasum

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

data : data/geoportal.statistics.gov.uk data/eea.europa.eu data/ons.gov.uk data/raw_catchments

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

# --------------------------------------------------------------------------------------------------

data/raw_catchments/anglian_water.zip :
	$(info Anglian Water has not provided the data as an attachment to the Environmental Information \
		request; see https://www.whatdotheyknow.com/r/615f2df6-b1b3-42db-a236-8b311789a468 for \
		details. You can obtain the dataset by submitting your own request on whatdotheyknow.com, \
		emailing eir@anglianwater.co.uk using the Environmental Information Request \
		template in the README, or contacting the authors at till dot hoffmann at oxon dot org.)

data/raw_catchments/severn_trent_water.zip :
	$(info Severn Trent Water has not provided the data as an attachment to the Environmental \
		Information request; see https://www.whatdotheyknow.com/r/505e5178-c611-44f7-b6db-7f1e3c599e0e \
		for details. You can obtain the dataset by submitting your own request on whatdotheyknow.com, \
		emailing customerEIR@severntrent.co.uk using the Environmental Information Request \
		template in the README, or contacting the authors at till dot hoffmann at oxon dot org.)

COMPANIES = thames_water united_utilities welsh_water southern_water northumbrian_water \
	yorkshire_water scottish_water wessex_water
DOWNLOAD_URL_thames_water = https://www.whatdotheyknow.com/r/e5915cbb-dc3b-4797-bf75-fe7cd8eb75c0/response/1949301/attach/2/SDAC.zip
DOWNLOAD_URL_united_utilities = https://www.whatdotheyknow.com/r/578035f9-a422-4c1b-a803-c257bf4f3414/response/1948454/attach/3/UUDrainageAreas040122.zip
DOWNLOAD_URL_welsh_water = https://www.whatdotheyknow.com/r/f482d33f-e753-45b2-9518-45ddf92fa718/response/1948207/attach/3/DCWW%20Catchments.zip
DOWNLOAD_URL_southern_water = https://www.whatdotheyknow.com/r/4cde4e22-1df0-42c8-b1a2-02e2cbd45b1b/response/1938054/attach/3/swsdrain%20region.zip
DOWNLOAD_URL_northumbrian_water = https://www.whatdotheyknow.com/r/aad55c04-bbc4-47a9-bec8-ea7e2a97f6d3/response/1934324/attach/3/STW%20Catchments.zip
DOWNLOAD_URL_yorkshire_water = https://www.whatdotheyknow.com/r/639740ed-b0a3-4609-b4b6-a30a052fe037/response/1945306/attach/3/EIR%20Wastewater%20Catchments.zip
DOWNLOAD_URL_scottish_water = https://www.whatdotheyknow.com/r/0998addc-63f7-4a78-ac75-17fcf9b54b7d/response/1938176/attach/4/DOAs%20and%20WWTWs.zip
DOWNLOAD_URL_wessex_water = https://www.whatdotheyknow.com/r/bda33cfd-e23d-49e6-b651-4ff8997c83c3/response/1947874/attach/2/WxW%20WRC%20Catchments%20Dec2021.zip
DOWNLOAD_TARGETS = $(addprefix data/raw_catchments/,${COMPANIES:=.zip})

data/raw_catchments : data/raw_catchments/anglian_water.zip data/raw_catchments/severn_trent_water.zip \
	${DOWNLOAD_TARGETS}

${DOWNLOAD_TARGETS} : data/raw_catchments/%.zip :
	mkdir -p $(dir $@)
	curl -L -o $@ ${DOWNLOAD_URL_$*}

data.shasum : ${DOWNLOAD_TARGETS} \
		data/ons.gov.uk/lsoa_syoa_all_years_t.csv \
		data/geoportal.statistics.gov.uk/countries20_BGC.zip \
		data/geoportal.statistics.gov.uk/LSOA11_BGC.zip \
		data/eea.europa.eu/waterbase_v?_csv/T_UWWTPS.csv \
		data/eea.europa.eu/waterbase_v6_csv/dbo.VL_UWWTPS.csv \
		data/eea.europa.eu/waterbase_v?_csv/UWWTPS.csv
	shasum $^ > $@

data/validation :
	shasum -c data.shasum

# Processing of data ===============================================================================

analysis : workspace/consolidate_waterbase.html \
	workspace/consolidate_catchments.html \
	workspace/match_waterbase_and_catchments.html \
	workspace/estimate_population.html

${OUTPUT_ROOT} :
	mkdir -p $@

workspace :
	mkdir -p $@

workspace/consolidate_waterbase.html ${OUTPUT_ROOT}/waterbase_consolidated.csv \
		 : consolidate_waterbase.ipynb workspace ${OUTPUT_ROOT} data/eea.europa.eu
	${NBEXECUTE} $<

workspace/consolidate_catchments.html ${OUTPUT_ROOT}/catchments_consolidated.shp overview.pdf \
		: consolidate_catchments.ipynb workspace ${OUTPUT_ROOT} data/eir
	${NBEXECUTE} $<

workspace/match_waterbase_and_catchments.html ${OUTPUT_ROOT}/waterbase_catchment_lookup.csv \
		: match_waterbase_and_catchments.ipynb workspace ${OUTPUT_ROOT} \
		${OUTPUT_ROOT}/catchments_consolidated.shp ${OUTPUT_ROOT}/waterbase_consolidated.csv
	${NBEXECUTE} $<

workspace/match_catchments_and_lsoas.html ${OUTPUT_ROOT}/lsoa_coverage.csv \
	${OUTPUT_ROOT}/lsoa_catchment_lookup.csv \
		: match_catchments_and_lsoas.ipynb workspace ${OUTPUT_ROOT} \
		${OUTPUT_ROOT}/catchments_consolidated.shp data/geoportal.statistics.gov.uk
	${NBEXECUTE} $<

workspace/estimate_population.html ${OUTPUT_ROOT}/population_estimates.csv \
	population_estimates.pdf estimation_method.pdf \
		: estimate_population.ipynb data/ons.gov.uk workspace ${OUTPUT_ROOT} \
		${OUTPUT_ROOT}/lsoa_catchment_lookup.csv ${OUTPUT_ROOT}/lsoa_coverage.csv \
		${OUTPUT_ROOT}/waterbase_catchment_lookup.csv
	${NBEXECUTE} $<

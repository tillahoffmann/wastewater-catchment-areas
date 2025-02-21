.PHONY : clear_output data data/geoportal.statistics.gov.uk data/ons.gov.uk data/eea.europa.eu \
	data/raw_catchments data/validation data.shasum

NBEXECUTE = jupyter nbconvert --execute --output-dir=workspace --to=html
OUTPUT_ROOT = data/wastewater_catchment_areas_public
CURL = curl -L --retry 3 --retry-all-errors

requirements.txt : requirements.in
	pip-compile -v

sync : requirements.txt
	pip-sync

clear_output :
	jupyter nbconvert --clear-output *.ipynb

# Getting the data =================================================================================

data : data/eea.europa.eu data/geoportal.statistics.gov.uk data/ons.gov.uk data/raw_catchments

# --------------------------------------------------------------------------------------------------

data/geoportal.statistics.gov.uk : \
	data/geoportal.statistics.gov.uk/LSOA11_BGC.zip \
	data/geoportal.statistics.gov.uk/countries20_BGC.zip

# Generalised LSOA boundaries clipped to the coastline
# https://geoportal.statistics.gov.uk/datasets/ons::lower-layer-super-output-areas-december-2011-boundaries-generalised-clipped-bgc-ew-v3/about
data/geoportal.statistics.gov.uk/LSOA11_BGC.zip :
	mkdir -p $(dir $@)
	${CURL} -o $@ 'https://web.archive.org/web/20230316160948if_/https://opendata.arcgis.com/api/v3/datasets/a3940ee3ce4948f388e9993cb1d8cd0e_0/downloads/data?format=shp&spatialRefId=27700&where=1%3D1'

# Generalised countries clipped to the coastline
# https://geoportal.statistics.gov.uk/datasets/ons::countries-december-2020-uk-bgc/about
data/geoportal.statistics.gov.uk/countries20_BGC.zip :
	mkdir -p $(dir $@)
	${CURL} -o $@ 'https://web.archive.org/web/20240828001540/https://opendata.arcgis.com/api/v3/datasets/c8e90f1aaae34ac3ba3d79862000dbd7_0/downloads/data?format=shp&spatialRefId=27700&where=1%3D1'

# --------------------------------------------------------------------------------------------------

data/ons.gov.uk : data/ons.gov.uk/lsoa_syoa_all_years_t.csv

# Small area population estimates from 2001 to 2017
# https://www.ons.gov.uk/peoplepopulationandcommunity/populationandmigration/populationestimates/adhocs/009983populationestimatesforlowerlayersuperoutputareaslsoainenglandandwalessingleyearofageandsexmid2001tomid2017

data/ons.gov.uk/lsoa_syoa_all_years_t.csv :
	mkdir -p $(dir $@)
	${CURL} -o $(dir $@)/lsoasyoaallyearst.zip \
		'https://web.archive.org/web/20230316162603if_/https://www.ons.gov.uk/file?uri=/peoplepopulationandcommunity/populationandmigration/populationestimates/adhocs/009983populationestimatesforlowerlayersuperoutputareaslsoainenglandandwalessingleyearofageandsexmid2001tomid2017/lsoasyoaallyearst.zip'
	unzip -d $(dir $@) $(dir $@)/lsoasyoaallyearst.zip

# --------------------------------------------------------------------------------------------------

UWWTP_CSVS = data/eea.europa.eu/waterbase_v1_csv/T_UWWTPS.csv \
		data/eea.europa.eu/waterbase_v2_csv/T_UWWTPS.csv \
		data/eea.europa.eu/waterbase_v3_csv/T_UWWTPS.csv \
		data/eea.europa.eu/waterbase_v4_csv/T_UWWTPS.csv \
		data/eea.europa.eu/waterbase_v5_csv/T_UWWTPs.csv \
		data/eea.europa.eu/waterbase_v6_csv/dbo.VL_UWWTPS.csv \
		data/eea.europa.eu/waterbase_v7_csv/UWWTPS.csv \
		data/eea.europa.eu/waterbase_v8_csv/UWWTPS.csv

data/eea.europa.eu : ${UWWTP_CSVS}

${UWWTP_CSVS} : data/eea.europa.eu/download_waterbase.log

# Write a log file which the raw data rely on in the dependency graph. Otherwise, the download
# script is executed many times if `make` is launched with the `-j` option.
data/eea.europa.eu/download_waterbase.log :
	mkdir -p data/eea.europa.eu/
	python download_waterbase.py > ${@:.log=.log.tmp}
	mv ${@:.log=.log.tmp} $@

# --------------------------------------------------------------------------------------------------

COMPANIES = anglian_water thames_water united_utilities welsh_water southern_water northumbrian_water \
	yorkshire_water scottish_water severn_trent_water wessex_water
DOWNLOAD_URL_anglian_water = https://web.archive.org/web/20220325183050if_/https://www.whatdotheyknow.com/request/815216/response/2001959/attach/3/WWCATCHPOLY%2023%2004%202021.zip
DOWNLOAD_URL_thames_water = https://web.archive.org/web/20230316161703if_/https://www.whatdotheyknow.com/r/e5915cbb-dc3b-4797-bf75-fe7cd8eb75c0/response/1949301/attach/2/SDAC.zip
DOWNLOAD_URL_united_utilities = https://web.archive.org/web/20230316161811if_/https://www.whatdotheyknow.com/r/578035f9-a422-4c1b-a803-c257bf4f3414/response/1948454/attach/3/UUDrainageAreas040122.zip
DOWNLOAD_URL_welsh_water = https://web.archive.org/web/20230316161848if_/https://www.whatdotheyknow.com/r/f482d33f-e753-45b2-9518-45ddf92fa718/response/1948207/attach/3/DCWW%20Catchments.zip
DOWNLOAD_URL_southern_water = https://web.archive.org/web/20230316161903if_/https://www.whatdotheyknow.com/r/4cde4e22-1df0-42c8-b1a2-02e2cbd45b1b/response/1938054/attach/3/swsdrain%20region.zip
DOWNLOAD_URL_northumbrian_water = https://web.archive.org/web/20230316162136if_/https://www.whatdotheyknow.com/r/aad55c04-bbc4-47a9-bec8-ea7e2a97f6d3/response/1934324/attach/3/STW%20Catchments.zip
DOWNLOAD_URL_yorkshire_water = https://web.archive.org/web/20230316162204if_/https://www.whatdotheyknow.com/r/639740ed-b0a3-4609-b4b6-a30a052fe037/response/1945306/attach/3/EIR%20Wastewater%20Catchments.zip
DOWNLOAD_URL_scottish_water = https://web.archive.org/web/20230316162213/https://www.whatdotheyknow.com/r/0998addc-63f7-4a78-ac75-17fcf9b54b7d/response/1938176/attach/4/DOAs%20and%20WWTWs.zip
DOWNLOAD_URL_severn_trent_water = https://web.archive.org/web/20220613151243/https://www.stwater.co.uk/content/dam/stw/my-account/boundary-map-2022.zip
DOWNLOAD_URL_wessex_water = https://web.archive.org/web/20230316162447/https://www.whatdotheyknow.com/r/bda33cfd-e23d-49e6-b651-4ff8997c83c3/response/1947874/attach/2/WxW%20WRC%20Catchments%20Dec2021.zip
DOWNLOAD_TARGETS = $(addprefix data/raw_catchments/,${COMPANIES:=.zip})

# We seperately download the South West Water shape file because it is not a zip file.
SOUTH_WEST_WATER_TARGETS = $(addprefix data/raw_catchments/south_west_water.,shx shp prj dbf)
# TODO: Update to web archive urls once archived.
SOUTH_WEST_WATER_DOWNLOAD_URL_shp = https://www.whatdotheyknow.com/request/catchment_geospatial_data_files/response/2781770/attach/8/EIR24252%20CATCHMENT%20POLYGONS.shp
SOUTH_WEST_WATER_DOWNLOAD_URL_shx = https://www.whatdotheyknow.com/request/catchment_geospatial_data_files/response/2781770/attach/9/EIR24252%20CATCHMENT%20POLYGONS.shx
SOUTH_WEST_WATER_DOWNLOAD_URL_prj = https://www.whatdotheyknow.com/request/catchment_geospatial_data_files/response/2781770/attach/7/EIR24252%20CATCHMENT%20POLYGONS.prj
SOUTH_WEST_WATER_DOWNLOAD_URL_dbf = https://www.whatdotheyknow.com/request/catchment_geospatial_data_files/response/2781770/attach/6/EIR24252%20CATCHMENT%20POLYGONS.dbf

data/raw_catchments : ${DOWNLOAD_TARGETS} ${SOUTH_WEST_WATER_TARGETS}


${SOUTH_WEST_WATER_TARGETS} : data/raw_catchments/south_west_water.% :
	mkdir -p $(dir $@)
	${CURL} -o $@ ${SOUTH_WEST_WATER_DOWNLOAD_URL_$*}

${DOWNLOAD_TARGETS} : data/raw_catchments/%.zip :
	mkdir -p $(dir $@)
	${CURL} -o $@ ${DOWNLOAD_URL_$*}

data.shasum : ${DOWNLOAD_TARGETS} \
		${SOUTH_WEST_WATER_TARGETS} \
		data/ons.gov.uk/lsoa_syoa_all_years_t.csv \
		data/geoportal.statistics.gov.uk/countries20_BGC.zip \
		data/geoportal.statistics.gov.uk/LSOA11_BGC.zip \
		${UWWTP_CSVS}
	shasum $^ > $@

data/validation :
	shasum -c data.shasum

# Processing of data ===============================================================================

analysis : workspace/consolidate_waterbase.html \
	workspace/consolidate_catchments.html \
	workspace/match_waterbase_and_catchments.html \
	workspace/estimate_population.html \
	${OUTPUT_ROOT}/catchments_consolidated.zip

${OUTPUT_ROOT} :
	mkdir -p $@

workspace :
	mkdir -p $@

workspace/consolidate_waterbase.html ${OUTPUT_ROOT}/waterbase_consolidated.csv \
		 : consolidate_waterbase.ipynb workspace ${OUTPUT_ROOT} data/eea.europa.eu
	${NBEXECUTE} $<

workspace/consolidate_catchments.html ${OUTPUT_ROOT}/catchments_consolidated.shp overview.pdf \
		: consolidate_catchments.ipynb workspace ${OUTPUT_ROOT} data/raw_catchments
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

${OUTPUT_ROOT}/catchments_consolidated.zip : ${OUTPUT_ROOT}/catchments_consolidated.shp
	zip $@ ${@:.zip=}*

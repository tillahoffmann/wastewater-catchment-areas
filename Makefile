.PHONY : data data/geoportal.statistics.gov.uk data/environment.data.gov.uk docs

requirements.txt : requirements.in
	pip-compile -v

sync : requirements.txt
	pip-sync

docs :
	sphinx-build . docs/_build

# Getting the data =================================================================================

data : data/geoportal.statistics.gov.uk data/environment.data.gov.uk

# --------------------------------------------------------------------------------------------------

data/geoportal.statistics.gov.uk : \
	data/geoportal.statistics.gov.uk/LSOA11_BGC.zip \
	data/geoportal.statistics.gov.uk/LAD20_BGC.zip

# Generalised LSOA boundaries clipped to the coastline
# https://geoportal.statistics.gov.uk/datasets/ons::lower-layer-super-output-areas-december-2011-boundaries-generalised-clipped-bgc-ew-v3/about
data/geoportal.statistics.gov.uk/LSOA11_BGC.zip :
	mkdir -p $(dir $@)
	curl -L -o $@ 'https://opendata.arcgis.com/api/v3/datasets/8bbadffa6ddc493a94078c195a1e293b_0/downloads/data?format=shp&spatialRefId=27700'

# Generalised Local Authority Districts clipped to the coastline
# https://geoportal.statistics.gov.uk/datasets/ons::local-authority-districts-december-2020-uk-bgc/about
data/geoportal.statistics.gov.uk/LAD20_BGC.zip :
	mkdir -p $(dir $@)
	curl -L -o $@ 'https://opendata.arcgis.com/api/v3/datasets/db23041df155451b9a703494854c18c4_0/downloads/data?format=shp&spatialRefId=27700'

# --------------------------------------------------------------------------------------------------

data/environment.data.gov.uk : data/environment.data.gov.uk/RiverBasins.zip

# River catchment data
# https://environment.data.gov.uk/DefraDataDownload/?mapService=EA/WFDRiverBasinDistrictsCycle2&Mode=spatial
data/environment.data.gov.uk/RiverBasins.zip :
	mkdir -p $(dir $@)
	curl -L -o $@.tmp https://environment.data.gov.uk/UserDownloads/interactive/b40263fc97e24061afb8fa345bc3b14f47260/EA_WFDRiverBasinDistrictsCycle2_SHP_Full.zip
	# Unzip and remove temporary file
	unzip -u $@.tmp -d $@.dir
	rm $@.tmp
	# Rezip and remove directory
	zip -j $@ $@.dir/data/*
	rm -rf $@.dir

# Processing the data ==============================================================================

example : workspace/RiverBasins_LAD20_BGC.json

workspace/RiverBasins_LAD20_BGC.json : data/environment.data.gov.uk/RiverBasins.zip data/geoportal.statistics.gov.uk/LAD20_BGC.zip
	python geomapping.py $(addprefix zip://,$^) $@

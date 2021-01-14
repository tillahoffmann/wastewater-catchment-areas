.PHONY : data data/geoportal.statistics.gov.uk data/environment.data.gov.uk docs

requirements.txt : requirements.in
	pip-compile -v

sync : requirements.txt
	pip-sync

docs :
	sphinx-build . docs/_build

# Getting the data =================================================================================

data : data/geoportal.statistics.gov.uk data/environment.data.gov.uk data/arcgis.com

# --------------------------------------------------------------------------------------------------

data/geoportal.statistics.gov.uk : \
	data/geoportal.statistics.gov.uk/LSOA11_BGC.zip \
	data/geoportal.statistics.gov.uk/LAD20_BGC.zip

# Generalised LSOA boundaries clipped to the coastline
# https://geoportal.statistics.gov.uk/datasets/lower-layer-super-output-areas-december-2011-ew-bgc-v2
data/geoportal.statistics.gov.uk/LSOA11_BGC.zip :
	mkdir -p $(dir $@)
	curl -L -o $@ https://opendata.arcgis.com/datasets/42f3aa4ca58742e8a55064a213fb27c9_0.zip

# Generalised Local Authority Districts clipped to the coastline
# https://geoportal.statistics.gov.uk/datasets/local-authority-districts-may-2020-boundaries-uk-bgc-1
data/geoportal.statistics.gov.uk/LAD20_BGC.zip :
	mkdir -p $(dir $@)
	curl -L -o $@ https://opendata.arcgis.com/datasets/3b374840ce1b4160b85b8146b610cd0c_0.zip?outSR=%7B%22latestWkid%22%3A27700%2C%22wkid%22%3A27700%7D

# --------------------------------------------------------------------------------------------------

data/environment.data.gov.uk : data/environment.data.gov.uk/RiverBasins.zip

# River catchment data
# https://environment.data.gov.uk/DefraDataDownload/?mapService=EA/WFDRiverBasinDistrictsCycle2&Mode=spatial
data/environment.data.gov.uk/RiverBasins.zip :
	mkdir -p $(dir $@)
	curl -L -o $@.tmp https://environment.data.gov.uk/UserDownloads/interactive/38e8c96bbd614d009e65532fdfda4a09100380/EA_WFDRiverBasinDistrictsCycle2_SHP_Full.zip
	# Unzip and remove temporary file
	unzip -u $@.tmp -d $@.dir
	rm $@.tmp
	# Rezip and remove directory
	zip -j $@ $@.dir/data/*
	rm -rf $@.dir

# --------------------------------------------------------------------------------------------------

data/arcgis.com : data/arcgis.com/GBR_PostcodeSector.geojson

data/arcgis.com/GBR_PostcodeSector.geojson :
	python download_arcgis_dataset.py --username=${NAME} --password=${PASSWORD} \
		--layer=$(notdir ${@:.geojson=}) d7542e434a5045d19cff3bd09536720d $(dir $@)

# Processing the data ==============================================================================

example : workspace/RiverBasins_LAD20_BGC.json

workspace/RiverBasins_LAD20_BGC.json : data/environment.data.gov.uk/RiverBasins.zip data/geoportal.statistics.gov.uk/LAD20_BGC.zip
	python geomapping.py $(addprefix zip://,$^) $@

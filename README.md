# WCDAS
## Water Color Data Analysis System

The WCDAS is a tool to promote the operational generation of maps and indicators useful in the monitoring of water quality. 
The WC-DAS facilitates data processing of satellite optical multispectral data acquired by Sentinel-3 OLCI, Sentinel-2 MSI and Landsat-8 OLI sensors. Users can optionally provide a set of calibrated parameters to process a list of input satellite data. 
The algorithms Case 2 Regional CoastColour (C2RCC) (Brockmann et al., 2016) and Atmospheric Correction for OLI 'lite' (ACOLITE) (Vanhellemont et al., 2016) are implemented: they perform atmospheric correction to derive water-leaving reflectances from Top-Of-Atmospere reflectances, that are later used for water quality parameters estimation.
Regional calibrated coefficients, desirable by retrieval algorithms for an accurate estimation of seawater bio-geophysical parameters considering local conditions, can be optionally supplied in order to operationally deriving calibrated water quality estimates.

### Main features:

* integrates C2RCC and ACOLITE algorithms
* user can provide in situ measured pressure data
* allows the use of algorithm calibrated parameters
* optionally save atmospherically corrected water leaving reflectances
* parallel processing using multiple CPUs

### Supported data:

* Sentinel-3 OLCI
* Sentinel-2 MSI
* LANDSAT8 OLI

### C2RCC features:

* optionally save Inherent Optical Properties (IOPs) estimates

### ACOLITE features:

* optionally perform sun-glint correction (only Sentinel-2 MSI data)

### Authors

* Filipponi Federico

### License

Licensed under the GNU General Public License, Version 3.0: https://www.gnu.org/licenses/gpl-3.0.html

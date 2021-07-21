#!/bin/env bash

#######################################################
#
# Script Name: S2_C2RCC.sh
# Version: 0.5.1
#
# Author: Federico Filipponi
# Date : 11.06.2021
#
# Copyright name: CC BY-NC-SA
# License: GPLv3
#
# Purpose: Estimate water color bio-geophysical parameters from Copernicus Sentinel-2 MSI data using C2RCC algorithm
#
# Description: 
# Usage: S2_acolite.sh -k -r -o /data/output -f /S2A_20210608.zip -p /repository/dev/hm-wp6000/ff/river_color/auxiliary_files/Pressure_data.csv -w /dati/workspace
#
#######################################################

### to be done:
# - using R script with input shapefile mask
# - define which C2RCC algorithm nnet to be used (i.e. C2X)
# - named presets formula for water mask (and optionally user defined)
# - define salinity values (for rivers use '0.1')

# Set Help function
Help()
{
  # Display command help
  echo "Usage : S2_C2RCC.sh [Options] -f S2A_20210608.zip -o /space/output"
  echo ""
  echo "Options:"
  echo "    -a             Set algorithm (must be one of the followings: 'C2RCC' (default), 'C2X', 'C2XC')"
  echo "    -c             Calibration parameters file (optional)"
  echo "    -f <file>      Input file"
  echo "    -h             Help information for the operator"
  echo "    -i             Keep IOPs intermediate products (optional)"
  echo "    -k             Keep intermediate products (optional)"
  echo "    -o <output>    Output file name"
  echo "    -p             Pressure data (optional)"
  echo "    -q <cores>     Number of cores to be used (optional)"
  echo "    -r             Keep Rhow intermediate products (optional)"
  echo "    -u             Output uncertainties (optional)"
  echo "    -v             Verbose mode"
  echo "    -w <folder>    Set temporary working directory (optional)"
  # echo ""
  # echo "  S2_C2RCC.sh 0.5.1, GPL v3, CC BY-NC-SA 2018-2021 Federico Filipponi"
  # echo "  This is free software and comes with ABSOLUTELY NO WARRANTY"
}

# set default options
ALGORITHM="C2RCC"
N_ALGORITHM="C2RCC"
UNCERTAINTY="false"

# get options
while getopts ":a:c:f:o:p:q:w:ikruvh" opt; do
  case $opt in
    f)
      FILE=$OPTARG
      ;;
    o)
      OUTPUTDIR=$OPTARG
      ;;
    p)
      PRESSURE_DATA=$OPTARG
      ;;
    c)
      CALIBRATED_PARAM=$OPTARG
      ;;
    a)
      N_ALGORITHM=$OPTARG
      ;;
    w)
      WORKINGDIR=$OPTARG
      ;;
    q)
      CORES=$OPTARG
      ;;
    k)
      KEEP="TRUE"
      ;;
    r)
      RHOW="TRUE"
      ;;
    i)
      IOP="TRUE"
      ;;
    u)
      UNCERTAINTY="true"
      ;;
    v)
      VERBOSE="TRUE"
      ;;
    h)
      Help
      exit 1
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      exit 1
      ;;
    :a:c:f:o:p:q:w:)
      echo "Option -$OPTARG requires an argument." >&2
      exit 1
      ;;
  esac
done

#########################################
# check input arguments
# echo $OUTPUTDIR $FILE $WORKINGDIR $PRESSURE_DATA

if [ $# -eq 0 ]
then
  Help
  exit 1
fi

if [ -z $FILE ]
then
  echo "Error: Provide one input file using the '-f' argument." >&2
  exit 1
fi

if [ ! -f $FILE ] && [ ! -z $FILE ]
then
  echo "Error: File set using the '-f' argument does not exists." >&2
  exit 1
fi

if [ -z $OUTPUTDIR ]
then
  echo "Error: Output path not set using the '-o' argument." >&2
  exit 1
fi

if [ ! -f $PRESSURE_DATA ] && [ ! -z $PRESSURE_DATA ]
then
  echo "Warning: Pressure data file set using the '-p' argument does not exists. Going on without using pressure data." >&2
fi

if [ ! "$N_ALGORITHM" == "C2RCC" ] && [ ! "$N_ALGORITHM" == "C2X" ] && [ ! "$N_ALGORITHM" == "C2XC" ]
then
  echo "Error: One retrieval algorithm should be selected among 'C2RCC' (default), 'C2X', 'C2XC'." >&2
  exit 1
fi

# set C2RCC Neural Nets set to be used
if [ "$N_ALGORITHM" != "C2RCC" ]
then
  ALGORITHM_NETS="C2RCC-Nets"
elif [ "$N_ALGORITHM" != "C2X" ]
then
  ALGORITHM_NETS="C2X-Nets"
elif [ "$N_ALGORITHM" != "C2XC" ]
then
  ALGORITHM_NETS="C2X-COMPLEX-Nets"
fi

OUTPUTDIR=${OUTPUTDIR%%/}

# check number of cores
CORES=$((CORES + 0))

MACHINE_CORES=`nproc`
MACHINE_CORES=$((MACHINE_CORES + 0))

if [[ $CORES -eq 0 ]]
then
  CORES=$MACHINE_CORES
fi
if [[ $CORES -gt $MACHINE_CORES ]]
then
  CORES=$MACHINE_CORES
fi

# get environmental variables
# SCRIPT_HOME="$( cd "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
SCRIPT_HOME=${PROCESSOR_HOME}

if [ "$SCRIPT_HOME" == "" ]
then
  echo "Error: Environmental variable 'SCRIPT_HOME' not set." >&2
  exit 1
fi

# set graphs paths
# C2RCC_IOP_SUBSET_XML=${SCRIPT_HOME}/graphs/WaterColor_C2RCC_IOPs_subset.xml
C2RCC_IOP_SUBSET_XML=${SCRIPT_HOME}/graphs/WaterColor_C2RCC_IOPs_subset_turbidity.xml
C2RCC_IOP_INTERMEDIATE_XML=${SCRIPT_HOME}/graphs/WaterColor_C2RCC_IOPs_intermediate.xml
C2RCC_IOP_UNCERTAINTY_XML=${SCRIPT_HOME}/graphs/WaterColor_C2RCC_IOPs_uncertainty.xml
C2RCC_RHOW_XML=${SCRIPT_HOME}/graphs/WaterColor_C2RCC_Rhow.xml
S2_RR_10M_XML=${SCRIPT_HOME}/graphs/WaterColor_S2resampling_10m.xml

# set SNAP options
# SNAP_OPT="-Djava.io.tmpdir=/shared/workspace/prepro -c 24G"
SNAP_OPT=""

#########################################
#echo "Water Color processor - Process Sentinel-2 MSI using 'C2RCC' algorithm - v0.5.1"
#echo ""
#########################################
# time starting
T0="$(date +%s%N)"

#########
# for debug
# FILE="/repository/lavisam/hub/sentinel_hub/sentinel2/l1c/T32TPQ/2016/S2A_MSIL1C_20160701T102022_N0204_R065_T32TPQ_20160701T102057.zip"
# OUTPUTDIR="/repository/dev/hm-wp6000/ff/river_color/test01"
# WORKINGDIR="/dati/workspace/f.filipponi"
# PRESSURE_DATA="/space/filipfe_data/me/arpav/lago_santa_croce/auxiliary_files/insitu/Pressure_data.csv"
# KEEP="TRUE"
# RHOW="TRUE"
# IOP="TRUE"
# UNCERTAINTY="true"
# CORES=10
# VERBOSE="TRUE"

echo "###########################################################################################################"
echo "Processing file: '${FILE}'"
if [ "$VERBOSE" == "TRUE" ]
then
  echo "Started at: $(date)"
fi

#########################################
# Set variables from file name

# extract file basename
BASENAME=$(basename $FILE .zip)
# extract stellite name
SAT_NAME=${BASENAME:0:3}
# extract granule
GRANULE=${BASENAME:38:6}

# extract acquisition year
ACQ_YEAR=${BASENAME:11:4}
# extract acquisition date
ACQ_DATE=${BASENAME:11:15}

# set file root path name
FRPN="${GRANULE}__${ACQ_DATE}_${SAT_NAME}"
# set file root path
FRP=$(echo "${OUTPUTDIR%%/}/${GRANULE}/${ACQ_YEAR}/${FRPN}" | sed 's#//#/#g')

# set temporary working directory
if [ ! -z $WORKINGDIR ]
then
  # set file basename
  FRW=$(echo "${WORKINGDIR%%/}/${GRANULE}/${ACQ_YEAR}/${FRPN}" | sed 's#//#/#g')
  BNAME="${FRW}/${FRPN}"
  if [ "$VERBOSE" == "TRUE" ]
  then
    echo "Results will be temporary stored in the directory '${FRW}'"
  fi
else
  FRW=${FRP}
  # set file basename
  BNAME="${FRP}/${FRPN}"
fi

if [ "$VERBOSE" == "TRUE" ]
then
  echo "Results will be stored in the directory '$FRP'"
fi

# process data if output file does not exist
if [ -f "${FRP}/${FRPN}_L2B_${ALGORITHM}_TSM.tif" ] && [ -f "${FRP}/${FRPN}_L2B_${ALGORITHM}_CHL.tif" ]
then
  echo "Info: Output products for '${FILE}' already exist. Skipping ..."
else
  
  # create output folder
  mkdir -p ${FRW}

  ######################
  # set granules regions
  ### to be done: using R script with input shapefile mask

  # create output file names
  OUTPUTPATH_10m="${BNAME}_L2B_${ALGORITHM}_10m.dim"
  OUTPUTPATH_C2RCC="${BNAME}_L2B_${ALGORITHM}.dim"
  OUTPUTPATH_C2RCC_DATA="${BNAME}_L2B_${ALGORITHM}.data"
  OUTPUTPATH_CHL="${BNAME}_L2B_${ALGORITHM}_CHL_tmp.tif"
  OUTPUTPATH_TSM="${BNAME}_L2B_${ALGORITHM}_TSM_tmp.tif"
  OUTPUTPATH_TUR="${BNAME}_L2B_${ALGORITHM}_TUR_tmp.tif"
  OUTPUT_CHL="${BNAME}_L2B_${ALGORITHM}_CHL.tif"
  OUTPUT_TSM="${BNAME}_L2B_${ALGORITHM}_TSM.tif"
  OUTPUT_TUR="${BNAME}_L2B_${ALGORITHM}_turbidity.tif"

  # set C2RCC parameters
  ### to be done: allow user defined formula or already defined named presets

  #P_PIXEL_EXPRESSION=`echo '(B2 &gt; 0 and B3 &gt; 0 and B4 &gt; 0 and B8 &gt; 0 and B8 &lt; 0.15 and B11 &lt; 0.03 and B8 &lt; B3 and B8 &lt; B2 and ((B2 + B3 + B4) &gt; 0.20))'`
  #P_PIXEL_EXPRESSION='(B2 > 0 and B3 > 0 and B4 > 0 and B8 > 0 and B8 < 0.15 and B11 < 0.03 and B8 < B3 and B8 < B2 and ((B2 + B3 + B4) > 0.20))'
  #P_PIXEL_EXPRESSION='(B1 > 0 and B2 > 0 and B3 > 0 and B4 > 0 and B5 > 0 and B6 > 0 and B7 > 0 and B8 > 0 and B8A > 0 and B11 > 0 and B12 > 0 and B8 < 0.15 and B11 < 0.03 and B8 < B3 and B8 < B2 and ((B2 + B3 + B4) > 0.20))'

  # formula for rivers
  #P_PIXEL_EXPRESSION='(B1 > 0 and B2 > 0 and B3 > 0 and B4 > 0 and B5 > 0 and B6 > 0 and B7 > 0 and B8 > 0 and B8A > 0 and B11 > 0 and B12 > 0 and B8 < 0.35 and B11 < 0.03 and B8 < (B3 + (B8 / 3.0)) and B8 < (B2 + (B8 / 3.0) ) and ((B2 + B3 + B4) > 0.20))'

  # formula for coastal waters
  P_PIXEL_EXPRESSION='(B1 > 0 and B2 > 0 and B3 > 0 and B4 > 0 and B5 > 0 and B6 > 0 and B7 > 0 and B8 > 0 and B8A > 0 and B11 > 0 and B12 > 0 and B8 < 0.35 and B11 < 0.03 and B8 < (B3 + (B8 / 3.0)) and B8 < (B2 + (B8 / 3.0) ))'

  # set default parameters
  P_SALINITY="35.0"
  # P_SALINITY="0.1"
  P_TEMPERATURE="15.0"
  P_ELEVATION="0"
  P_PRESSURE="1000.0"

  # get pressure value from in situ data
  if [ -n "$PRESSURE_DATA" ]
  then
    if [ -f $PRESSURE_DATA ]
    then
      ACQ_DAY=${ACQ_DATE:0:8}
      # check Windows newline and extract pressure
      P_PRESSURE=$(sed -n -e "s/\r$//" -e "s/^${ACQ_DAY};//p" ${PRESSURE_DATA})
      P_PRESSURE=$(echo "$P_PRESSURE" | bc)

      if [ "$P_PRESSURE" == "" ]
      then
        P_PRESSURE="1000.0"
      else
        # check if pressure value is within range
        if (( $(echo "$P_PRESSURE < 870"  | bc -l) )) || (( $(echo "$P_PRESSURE > 1085" | bc -l) ))
        then
          if [ "$VERBOSE" == "TRUE" ]
          then
            echo "WARNING User defined pressure value '${P_PRESSURE}' hPa is outside allowed range '870.0' hPa - '1085.0' hPa. Using default pressure value: '1000.0' hPa" >&2
          fi
          P_PRESSURE="1000.0"
        else
          if [ "$VERBOSE" == "TRUE" ]
          then
            echo "INFO Using pressure value from insitu data: '${P_PRESSURE}' hPa"
          fi
        fi
      fi
    fi
  fi

  # set retrieval default parameters
  TSM_fac=1.06
  TSM_exp=0.942
  CHL_fac=21.0
  CHL_exp=1.04
  A_T_red=228.1
  C_T_red=0.1641
  A_T_nir=3078.9
  C_T_nir=0.2112

  # get calibrated parameters from file
  if [ -n "$CALIBRATED_PARAM" ]
  then
    if [ -f $CALIBRATED_PARAM ]
    then
      TSM_fac=$(sed -n -e "s/^TSM_fac=//p" ${CALIBRATED_PARAM})
      TSM_exp=$(sed -n -e "s/^TSM_exp=//p" ${CALIBRATED_PARAM})
      CHL_fac=$(sed -n -e "s/^CHL_fac=//p" ${CALIBRATED_PARAM})
      CHL_exp=$(sed -n -e "s/^CHL_exp=//p" ${CALIBRATED_PARAM})
      A_T_red=$(sed -n -e "s/^A_T_red=//p" ${CALIBRATED_PARAM})
      C_T_red=$(sed -n -e "s/^C_T_red=//p" ${CALIBRATED_PARAM})
      A_T_nir=$(sed -n -e "s/^A_T_nir=//p" ${CALIBRATED_PARAM})
      C_T_nir=$(sed -n -e "s/^C_T_nir=//p" ${CALIBRATED_PARAM})
      ### to be done: add check for pressure value
      if [ "$VERBOSE" == "TRUE" ]
      then
        echo "Info: Using calibrated parameters:"
        cat ${CALIBRATED_PARAM}
      fi
    fi
  fi

  # set KD output argument
  if [ "$IOP" == "TRUE" ]
  then
    OUT_KD="true"
  else
    OUT_KD="false"
  fi

  #########################################
  # Extract file

  if [ "$VERBOSE" == "TRUE" ]
  then
    echo "Extracting zip archive to ${FRW} ..."
  fi
  unzip -o -q ${FILE} -d ${FRW}

  # set S2 L1C file path
  L1C_NAME="${FRW}/${BASENAME}.SAFE"

  #########################################
  # Run C2RCC algorithm

  # set default region
  SUBSET_REGION='0,0,10980,10980'
  REG_NAME=$GRANULE"_REGION"

  # set the default region if not set
  if [ -n "$REG_NAME" ]
  then
    # set custom region
    GET_REGION=`echo $REG_NAME`
    SUBSET_REGION=`echo ${!GET_REGION}`
  else
    # set default region
    SUBSET_REGION='0,0,10980,10980'
  fi

  # resample data to 10 m and clip to region extent
  gpt ${S2_RR_10M_XML} -Pregion=${SUBSET_REGION} -Pinput=${L1C_NAME} -Poutput=${OUTPUTPATH_10m} -q ${CORES} ${SNAP_OPT}

  # run C2RCC algorithm
  gpt c2rcc.msi -SsourceProduct=${OUTPUTPATH_10m} -f "BEAM-DIMAP" -t ${OUTPUTPATH_C2RCC} -Psalinity=${P_SALINITY} -Ptemperature=${P_TEMPERATURE} -Pelevation=${P_ELEVATION} -Ppress=${P_PRESSURE} -PnetSet=${ALGORITHM_NETS} -PTSMfac=${TSM_fac} -PTSMexp=${TSM_exp} -PCHLfac=${CHL_fac} -PCHLexp=${CHL_exp} -PoutputKd=${OUT_KD} -PoutputRhown="false" -PoutputRtoa="false" -PoutputAsRrs="false" -PoutputUncertainties=${UNCERTAINTY} -PvalidPixelExpression="${P_PIXEL_EXPRESSION}" -q ${CORES} ${SNAP_OPT}

  # extract Chl and TSM bands and compute turbidity
  gpt ${C2RCC_IOP_SUBSET_XML} -Pinput=${OUTPUTPATH_C2RCC} -Poutput_chl=${OUTPUTPATH_CHL} -Poutput_tsm=${OUTPUTPATH_TSM} -Poutput_turbidity=${OUTPUTPATH_TUR} -PATred=${A_T_red} -PCTred=${C_T_red} -PATnir=${A_T_nir} -PCTnir=${C_T_nir} -q ${CORES} ${SNAP_OPT}

  # set NA value to output GeoTIFF bands
  gdal_translate -q -of GTiff -ot UInt16 -a_nodata 65535 -a_scale 0.01 -a_offset 0.0 -co "COMPRESS=LZW" -mo "ALGORITHM=${ALGORITHM}" -mo "C2RCC-Nets=${ALGORITHM_NETS}" -mo "CHLfac=${CHL_fac}" -mo "CHLexp=${CHL_exp}" ${OUTPUTPATH_CHL} ${OUTPUT_CHL}
  gdal_translate -q -of GTiff -ot UInt16 -a_nodata 65535 -a_scale 0.01 -a_offset 0.0 -co "COMPRESS=LZW" -mo "ALGORITHM=${ALGORITHM}" -mo "C2RCC-Nets=${ALGORITHM_NETS}" -mo "TSMfac=${TSM_fac}" -mo "TSMexp=${TSM_exp}" ${OUTPUTPATH_TSM} ${OUTPUT_TSM}
  gdal_translate -q -of GTiff -ot Int16 -a_nodata -32768 -a_scale 0.02 -a_offset 500.0 -co "COMPRESS=LZW" -mo "ALGORITHM=${ALGORITHM}" -mo "C2RCC-Nets=${ALGORITHM_NETS}" -mo "A_T_red=${A_T_red}" -mo "C_T_red=${C_T_red}" -mo "A_T_nir=${A_T_nir}" -mo "C_T_nir=${C_T_nir}" -mo "Turbidity=Dogliotti" ${OUTPUTPATH_TUR} ${OUTPUT_TUR}

  rm -rf ${OUTPUTPATH_CHL} ${OUTPUTPATH_TSM} ${OUTPUTPATH_TUR}

  # save uncertainties to GeoTIFF
  if [ "$UNCERTAINTY" == "true" ]
  then

    if [ "$VERBOSE" == "TRUE" ]
    then
      echo "Exporting uncertainties to GeoTIFF ..."
    fi

    OUTPUTPATH_CHL_UNC="${BNAME}_L2B_${ALGORITHM}_chl_unc_tmp.tif"
    OUTPUTPATH_TSM_UNC="${BNAME}_L2B_${ALGORITHM}_tsm_unc_tmp.tif"
    OUTPUT_CHL_UNC="${BNAME}_L2B_${ALGORITHM}_CHL_uncertainty.tif"
    OUTPUT_TSM_UNC="${BNAME}_L2B_${ALGORITHM}_TSM_uncertainty.tif"

    # extract Chl and TSM bands uncertainties
    gpt ${C2RCC_IOP_UNCERTAINTY_XML} -Pinput=${OUTPUTPATH_C2RCC} -Poutput_chl_uncertainty=${OUTPUTPATH_CHL_UNC} -Poutput_tsm_uncertainty=${OUTPUTPATH_TSM_UNC} -q ${CORES} ${SNAP_OPT}

    # convert to LZW compressed GeoTIFF
    gdal_translate -q -of GTiff -ot UInt16 -a_nodata 65535 -a_scale 0.01 -a_offset 0.0 -co "COMPRESS=LZW" -mo "ALGORITHM=${ALGORITHM}" -mo "C2RCC-Nets=${ALGORITHM_NETS}" -mo "CHLfac=${CHL_fac}" -mo "CHLexp=${CHL_exp}" ${OUTPUTPATH_CHL_UNC} ${OUTPUT_CHL_UNC}
    gdal_translate -q -of GTiff -ot UInt16 -a_nodata 65535 -a_scale 0.01 -a_offset 0.0 -co "COMPRESS=LZW" -mo "ALGORITHM=${ALGORITHM}" -mo "C2RCC-Nets=${ALGORITHM_NETS}" -mo "TSMfac=${TSM_fac}" -mo "TSMexp=${TSM_exp}" ${OUTPUTPATH_TSM_UNC} ${OUTPUT_TSM_UNC}

    # remove temporary files
    rm -rf ${OUTPUTPATH_CHL_UNC} ${OUTPUTPATH_TSM_UNC}

  fi

  # save intermediate IOPs to GeoTIFF
  if [ "$IOP" == "TRUE" ]
  then

    if [ "$VERBOSE" == "TRUE" ]
    then
      echo "Exporting IOPs to GeoTIFF ..."
    fi

    OUTPUTPATH_APIG="${BNAME}_L2B_${ALGORITHM}_apig_tmp.tif"
    OUTPUTPATH_BPART="${BNAME}_L2B_${ALGORITHM}_bpart_tmp.tif"
    OUTPUTPATH_BWIT="${BNAME}_L2B_${ALGORITHM}_bwit_tmp.tif"
    OUTPUTPATH_Z90MAX="${BNAME}_L2B_${ALGORITHM}_z90max_tmp.tif"
    OUTPUT_APIG="${BNAME}_L2B_${ALGORITHM}_APIG.tif"
    OUTPUT_BPART="${BNAME}_L2B_${ALGORITHM}_BPART.tif"
    OUTPUT_BWIT="${BNAME}_L2B_${ALGORITHM}_BWIT.tif"
    OUTPUT_Z90MAX="${BNAME}_L2B_${ALGORITHM}_z90_max.tif"

    # extract Chl and TSM bands
    gpt ${C2RCC_IOP_INTERMEDIATE_XML} -Pinput=${OUTPUTPATH_C2RCC} -Poutput_apig=${OUTPUTPATH_APIG} -Poutput_bpart=${OUTPUTPATH_BPART} -Poutput_bwit=${OUTPUTPATH_BWIT} -Poutput_z90max=${OUTPUTPATH_Z90MAX} -q ${CORES} ${SNAP_OPT}

    # convert to LZW compressed GeoTIFF
    gdal_translate -q -of GTiff -ot UInt16 -a_nodata 65535 -a_scale 0.01 -a_offset 0.0 -co "COMPRESS=LZW" -mo "ALGORITHM=${ALGORITHM}" -mo "C2RCC-Nets=${ALGORITHM_NETS}" ${OUTPUTPATH_APIG} ${OUTPUT_APIG}
    gdal_translate -q -of GTiff -ot UInt16 -a_nodata 65535 -a_scale 0.01 -a_offset 0.0 -co "COMPRESS=LZW" -mo "ALGORITHM=${ALGORITHM}" -mo "C2RCC-Nets=${ALGORITHM_NETS}" ${OUTPUTPATH_BPART} ${OUTPUT_BPART}
    gdal_translate -q -of GTiff -ot UInt16 -a_nodata 65535 -a_scale 0.01 -a_offset 0.0 -co "COMPRESS=LZW" -mo "ALGORITHM=${ALGORITHM}" -mo "C2RCC-Nets=${ALGORITHM_NETS}" ${OUTPUTPATH_BWIT} ${OUTPUT_BWIT}
    gdal_translate -q -of GTiff -ot UInt16 -a_nodata 65535 -a_scale 0.01 -a_offset 0.0 -co "COMPRESS=LZW" -mo "ALGORITHM=${ALGORITHM}" -mo "C2RCC-Nets=${ALGORITHM_NETS}" ${OUTPUTPATH_Z90MAX} ${OUTPUT_Z90MAX}

    # remove temporary files
    rm -rf ${OUTPUTPATH_APIG} ${OUTPUTPATH_BPART} ${OUTPUTPATH_BWIT} ${OUTPUTPATH_Z90MAX}

  fi

  # save Rhow (Water Leaving Reflectances) to GeoTIFF
  if [ "$RHOW" == "TRUE" ]
  then

    if [ "$VERBOSE" == "TRUE" ]
    then
      echo "Exporting Rhow to GeoTIFF ..."
    fi

    OUTPUT_B_VRT="${BNAME}_L2A_${ALGORITHM}_Rhow.vrt"

    # extract reflectance bands
    gpt ${C2RCC_RHOW_XML} -Pinput=${OUTPUTPATH_C2RCC} -Poutput_b1=${BNAME}_L2A_${ALGORITHM}_B1_tmp.tif -Poutput_b2=${BNAME}_L2A_${ALGORITHM}_B2_tmp.tif -Poutput_b3=${BNAME}_L2A_${ALGORITHM}_B3_tmp.tif -Poutput_b4=${BNAME}_L2A_${ALGORITHM}_B4_tmp.tif -Poutput_b5=${BNAME}_L2A_${ALGORITHM}_B5_tmp.tif -Poutput_b6=${BNAME}_L2A_${ALGORITHM}_B6_tmp.tif -Poutput_b7=${BNAME}_L2A_${ALGORITHM}_B7_tmp.tif -Poutput_b8a=${BNAME}_L2A_${ALGORITHM}_B8A_tmp.tif -q ${CORES} ${SNAP_OPT}

    # convert to LZW compressed GeoTIFF
    gdal_translate -q -of GTiff -ot UInt16 -a_nodata 65535 -a_scale 0.0001 -a_offset 0 -co "COMPRESS=LZW" ${BNAME}_L2A_${ALGORITHM}_B1_tmp.tif ${BNAME}_L2A_${ALGORITHM}_Rhow_B1.tif
    gdal_translate -q -of GTiff -ot UInt16 -a_nodata 65535 -a_scale 0.0001 -a_offset 0 -co "COMPRESS=LZW" ${BNAME}_L2A_${ALGORITHM}_B2_tmp.tif ${BNAME}_L2A_${ALGORITHM}_Rhow_B2.tif
    gdal_translate -q -of GTiff -ot UInt16 -a_nodata 65535 -a_scale 0.0001 -a_offset 0 -co "COMPRESS=LZW" ${BNAME}_L2A_${ALGORITHM}_B3_tmp.tif ${BNAME}_L2A_${ALGORITHM}_Rhow_B3.tif
    gdal_translate -q -of GTiff -ot UInt16 -a_nodata 65535 -a_scale 0.0001 -a_offset 0 -co "COMPRESS=LZW" ${BNAME}_L2A_${ALGORITHM}_B4_tmp.tif ${BNAME}_L2A_${ALGORITHM}_Rhow_B4.tif
    gdal_translate -q -of GTiff -ot UInt16 -a_nodata 65535 -a_scale 0.0001 -a_offset 0 -co "COMPRESS=LZW" ${BNAME}_L2A_${ALGORITHM}_B5_tmp.tif ${BNAME}_L2A_${ALGORITHM}_Rhow_B5.tif
    gdal_translate -q -of GTiff -ot UInt16 -a_nodata 65535 -a_scale 0.0001 -a_offset 0 -co "COMPRESS=LZW" ${BNAME}_L2A_${ALGORITHM}_B6_tmp.tif ${BNAME}_L2A_${ALGORITHM}_Rhow_B6.tif
    gdal_translate -q -of GTiff -ot UInt16 -a_nodata 65535 -a_scale 0.0001 -a_offset 0 -co "COMPRESS=LZW" ${BNAME}_L2A_${ALGORITHM}_B7_tmp.tif ${BNAME}_L2A_${ALGORITHM}_Rhow_B7.tif
    gdal_translate -q -of GTiff -ot UInt16 -a_nodata 65535 -a_scale 0.0001 -a_offset 0 -co "COMPRESS=LZW" ${BNAME}_L2A_${ALGORITHM}_B8A_tmp.tif ${BNAME}_L2A_${ALGORITHM}_Rhow_B8A.tif

    # create virtual raster stack
    gdalbuildvrt -q -separate ${OUTPUT_B_VRT} ${BNAME}_L2A_${ALGORITHM}_Rhow_B1.tif ${BNAME}_L2A_${ALGORITHM}_Rhow_B2.tif ${BNAME}_L2A_${ALGORITHM}_Rhow_B3.tif ${BNAME}_L2A_${ALGORITHM}_Rhow_B4.tif ${BNAME}_L2A_${ALGORITHM}_Rhow_B5.tif ${BNAME}_L2A_${ALGORITHM}_Rhow_B6.tif ${BNAME}_L2A_${ALGORITHM}_Rhow_B7.tif ${BNAME}_L2A_${ALGORITHM}_Rhow_B8A.tif

    # remove temporary files
    rm -rf ${BNAME}_L2A_${ALGORITHM}_B*_tmp.tif

  fi
  
  # remove temporary files
  rm -rf ${OUTPUTPATH_10m}
  RR_RM=${FRW}/$(basename $OUTPUTPATH_10m .dim).data
  rm -rf ${RR_RM}
  rm -rf ${L1C_NAME}

  # remove also part of the results to avoid large disk usage
  if [ ! "$KEEP" == "TRUE" ]
  then
    rm -rf ${OUTPUTPATH_C2RCC_DATA}
    rm -rf ${OUTPUTPATH_C2RCC}
  fi

   # remove output directory if empty
  if [ -z "$(ls -A ${FRW})" ]
  then
    rm -rf ${FRW}
  else
    # move data to target folder if a working directory was used
    if [ ! -z $WORKINGDIR ]
    then
      mkdir -p ${FRP}
      #FRF=$(dirname ${FRP})
      mv ${FRW}/* ${FRP}/
    fi
  fi

  # remove output directory if empty
  if [ -z "$(ls -A ${FRW})" ]
  then
    rm -rf ${FRW}
  fi

fi 

#########################################
if [ "$VERBOSE" == "TRUE" ]
then
  echo "Processing file '${FILE}' ended at: $(date)"
fi
T="$(($(date +%s%N)-T0))"
# Seconds
S="$((T/1000000000))"
# Milliseconds
M="$((T%1000000000/1000000))"
printf "Elapsed time: %02d:%02d:%02d:%02d.%03d\n" "$((S/86400))" "$((S/3600%24))" "$((S/60%60))" "$((S%60))" "${M}"
echo ""


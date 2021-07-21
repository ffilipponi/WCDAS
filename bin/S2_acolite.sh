#!/bin/env bash

#######################################################
#
# Script Name: S2_acolite.sh
# Version: 0.5.1
#
# Author: Federico Filipponi
# Date : 08.06.2021
#
# Copyright name: CC BY-NC-SA
# License: GPLv3
#
# Purpose: Estimate water color bio-geophysical parameters from Copernicus Sentinel-2 MSI data using ACOLITE algorithm
#
# Description: 
# Usage: S2_acolite.sh -k -r -o /data/output -f /S2A_20210608.zip -p /repository/dev/hm-wp6000/ff/river_color/auxiliary_files/Pressure_data.csv -w /dati/workspace
#
#######################################################

# Set Help function
Help()
{
  # Display command help
  echo "Usage : S2_acolite.sh [Options] -f S2A_20210608.zip -o /space/output"
  echo ""
  echo "Options:"
  echo "    -c             Calibration parameters file (optional)"
  echo "    -f <file>      Input file"
  echo "    -g             Perform sun glint correction (optional)"
  echo "    -h             Help information for the operator"
  echo "    -k             Keep intermediate products (optional)"
  echo "    -o <output>    Output file name"
  echo "    -p             Pressure data (optional)"
  echo "    -r             Keep Rhow intermediate products (optional)"
  echo "    -v             Verbose mode"
  echo "    -w <folder>    Set temporary working directory (optional)"
  # echo ""
  # echo "  S2_acolite.sh 0.5.1, GPL v3, CC BY-NC-SA 2018-2021 Federico Filipponi"
  # echo "  This is free software and comes with ABSOLUTELY NO WARRANTY"
}

# set default options
ALGORITHM="ACOLITE"

# get options
while getopts ":c:f:o:p:w:gkrvh" opt; do
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
    w)
      WORKINGDIR=$OPTARG
      ;;
    g)
      GLINT="TRUE"
      ;;
    k)
      KEEP="TRUE"
      ;;
    r)
      RHOW="TRUE"
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
    :c:f:o:p:w:)
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

OUTPUTDIR=${OUTPUTDIR%%/}

# get environmental variables
# SCRIPT_HOME="$( cd "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
SCRIPT_HOME=${PROCESSOR_HOME}

# make 'acolite' alias work in non interactive shell
# alias acolite='/home/apps/anaconda3/envs/acolite/bin/python /home/apps/acolite/launch_acolite.py'
shopt -s expand_aliases
source /etc/bashrc

if [ "$SCRIPT_HOME" == "" ]
then
  echo "Error: Environmental variable 'SCRIPT_HOME' not set." >&2
  exit 1
fi

# set configuration file path
# ACOLITE_CFG=${SCRIPT_HOME}/config/ACOLITE_config_S2.cfg
# use cfg for older acolite version
ACOLITE_CFG=${SCRIPT_HOME}/config/ACOLITE_config_S2_v20210114.cfg

# set SNAP options
# SNAP_OPT="-Djava.io.tmpdir=/shared/workspace/prepro -c 24G"
SNAP_OPT=""

#########################################
#echo "Water Color processor - Process Sentinel-2 MSI using 'ACOLITE' algorithm - v0.5.1"
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
if [ -f "${FRP}/${FRPN}_L2B_${ALGORITHM}_TSM.tif" ]
then
  echo "Info: Output products for '${FILE}' already exist. Skipping ..."
else
  
  # create output folder
  mkdir -p ${FRW}

  ######################
  # set granules regions
  # region bounding box for ACOLITE should be espress in LAT LONG coordinates (decimal degrees) in the following order: 'SOUTH,WEST,NORTH,WEST'
  
  ### to be done: using R script with input shapefile mask
  
  # create output file names
  OUTPUT_ACOLITE_CFG="${BNAME}_L2B_ACOLITE_config.cfg"
  OUTPUT_CHL="${BNAME}_L2B_${ALGORITHM}_CHL.tif"
  OUTPUT_TSM="${BNAME}_L2B_${ALGORITHM}_TSM.tif"
  OUTPUT_TUR="${BNAME}_L2B_${ALGORITHM}_turbidity.tif"

  # set Sun Glint correction
  if [ "$GLINT" == "TRUE" ]
  then
    ACOLITE_GLINTC="True"
  else
    ACOLITE_GLINTC="False"
  fi
  
  # set default ACOLITE pressure parameter
  P_PRESSURE="None"
  ZERO="0"

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
        P_PRESSURE="None"
      else
        # check if pressure value is within range
        if (( $(echo "$P_PRESSURE < 870"  | bc -l) )) || (( $(echo "$P_PRESSURE > 1085" | bc -l) ))
        then
          if [ "$VERBOSE" == "TRUE" ]
          then
            echo "WARNING User defined pressure value '${P_PRESSURE}' hPa is outside allowed range '870.0' hPa - '1085.0' hPa. Using default pressure value: '1013.25' hPa" >&2
          fi
          P_PRESSURE="None"
        else
          if [ "$VERBOSE" == "TRUE" ]
          then
            echo "INFO Using pressure value from insitu data: '${P_PRESSURE}' hPa"
          fi
        fi
      fi
    fi
  fi

  # get calibrated parameters from file
  if [ -n "$CALIBRATED_PARAM" ]
  then
    if [ -f $CALIBRATED_PARAM ]
    then
      ### import calibrated parameters here
      if [ "$VERBOSE" == "TRUE" ]
      then
        echo "Info: Using calibrated parameters."
      fi
    fi
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
  # Run ACOLITE algorithm
  
  # set default region
  SUBSET_REGION="None"
  
  # set ACOLITE parameters
  ACOLITE_REG_NAME=$GRANULE"_REGION"
  ACOLITE_LL_BB=${SUBSET_REGION}
  ACOLITE_OUTPUT_PATH=${FRW}
  ACOLITE_L2W_PARAMETERS="spm_nechad2016,t_dogliotti,chl_oc3"
  # ACOLITE_L2W_PARAMETERS="spm_nechad2016,t_nechad2016,chl_oc3"

  if [ "$RHOW" == "TRUE" ]
  then
    ACOLITE_RHOW="True"
    ACOLITE_L2W_PARAMETERS="${ACOLITE_L2W_PARAMETERS},Rhow_*"
  else
    ACOLITE_RHOW="False"
  fi
  
  if [ "$KEEP" == "TRUE" ]
  then
    ACOLITE_L2W_NC_DEL="False"
    ACOLITE_LOG_OUTPUT=${FRW}
    if [ "$RHOW" == "TRUE" ]
    then
      ACOLITE_L2R_NC_DEL="True"
    else
      ACOLITE_L2R_NC_DEL="False"
    fi
  else
    ACOLITE_L2R_NC_DEL="False"
    ACOLITE_L2W_NC_DEL="True"
    ACOLITE_LOG_OUTPUT="None"
  fi
  
  # create configuration file (.cfg) with parameters for ACOLITE processing
  sed -e "s@ACOLITE_REG_NAME@$ACOLITE_REG_NAME@g" -e "s@ACOLITE_LL_BB@$ACOLITE_LL_BB@g" -e "s@ACOLITE_OUTPUT_PATH@$ACOLITE_OUTPUT_PATH@g" -e "s@ACOLITE_LOG_OUTPUT@$ACOLITE_LOG_OUTPUT@g" -e "s@ACOLITE_L2W_PARAMETERS@$ACOLITE_L2W_PARAMETERS@g" -e "s@P_PRESSURE@$P_PRESSURE@g" -e "s@ACOLITE_GLINTC@$ACOLITE_GLINTC@g" -e "s@ACOLITE_L2R_NC_DEL@$ACOLITE_L2R_NC_DEL@g" -e "s@ACOLITE_L2W_NC_DEL@$ACOLITE_L2W_NC_DEL@g" -e "s@ACOLITE_RHOW@$ACOLITE_RHOW@g" ${ACOLITE_CFG} > ${OUTPUT_ACOLITE_CFG}
  
  # run ACOLITE algorithm
  if [ "$VERBOSE" == "TRUE" ]
  then
    echo "Running ACOLITE ..."
  fi

  # ####
  # run ACOLITE
  # acolite --cli --settings=${OUTPUT_ACOLITE_CFG} --inputfile=${L1C_NAME} --output=${FRW}

  # find output files
  # OUTPUTPATH_CHL=$(find $FRW -type f -name "*_chl_*.tif")
  # OUTPUTPATH_TSM=$(find $FRW -type f -name "*_SPM_*.tif")
  # OUTPUTPATH_TUR=$(find $FRW -type f -name "*_TUR_*.tif")
  
  # ####
  # use older stable version
  /home/apps/acolite_py_linux/dist/acolite/acolite --cli --settings=${OUTPUT_ACOLITE_CFG} --images=${L1C_NAME}
  
  # find output files
  OUTPUTPATH_CHL=$(find $FRW -type f -name "*_chl_*.tif")
  OUTPUTPATH_TSM=$(find $FRW -type f -name "*_spm_*.tif")
  OUTPUTPATH_TUR=$(find $FRW -type f -name "*_t_*.tif")
  
  # convert data to compressed GeoTIFF files ### add quiet mode
  /home/apps/anaconda3/envs/qgis/bin/gdal_calc.py --quiet --format=GTiff --type=UInt16 --NoDataValue=65535 --creation-option="COMPRESS=LZW" -A ${OUTPUTPATH_CHL} --outfile=${OUTPUT_CHL} --calc="where(A == 0, 65535, where(A > 655.3, 65535, A * 100.0))"
  /home/apps/anaconda3/envs/qgis/bin/gdal_calc.py --quiet --format=GTiff --type=UInt16 --NoDataValue=65535 --creation-option="COMPRESS=LZW" -A ${OUTPUTPATH_TSM} --outfile=${OUTPUT_TSM} --calc="where(A == 0, 65535, where(A > 655.3, 65535, A * 100.0))"
  /home/apps/anaconda3/envs/qgis/bin/gdal_calc.py --quiet --format=GTiff --type=UInt16 --NoDataValue=65535 --creation-option="COMPRESS=LZW" -A ${OUTPUTPATH_TUR} --outfile=${OUTPUT_TUR} --calc="where(A == 0, 65535, where(A > 1000, 65535, A * 10.0))"
  
  # set metadata for scale_factor and offset
  /home/apps/anaconda3/envs/qgis/bin/gdal_edit.py -scale 0.01 -offset 0 -mo "ALGORITHM=${ALGORITHM}" -mo "SUN_GLINT_CORRECTION=${ACOLITE_GLINTC}" -mo "CHL=chl_oc3" ${OUTPUT_CHL}
  /home/apps/anaconda3/envs/qgis/bin/gdal_edit.py -scale 0.01 -offset 0 -mo "ALGORITHM=${ALGORITHM}" -mo "SUN_GLINT_CORRECTION=${ACOLITE_GLINTC}" -mo "TSM=spm_nechad2016" ${OUTPUT_TSM}
  /home/apps/anaconda3/envs/qgis/bin/gdal_edit.py -scale 0.1 -offset 0 -mo "ALGORITHM=${ALGORITHM}" -mo "SUN_GLINT_CORRECTION=${ACOLITE_GLINTC}" -mo "Turbidity=Dogliotti" ${OUTPUT_TUR}
  
  # save Rhow (Water Leaving Reflectances) to GeoTIFF
  if [ "$RHOW" == "TRUE" ]
  then
  
    if [ "$VERBOSE" == "TRUE" ]
    then
      echo "Exporting Rhow to GeoTIFF ..."
    fi
  
    # get Sentinel-2 sensor
    S2_FILENAME=$(basename $L1C_NAME)
    S2_SENSOR=${S2_FILENAME:0:3}

    if [ "$S2_SENSOR" == "S2A" ]
    then
      OUTPUTPATH_B1=$(find $FRW -type f -name "*_rhos_443.tif")
      OUTPUTPATH_B2=$(find $FRW -type f -name "*_rhos_492.tif")
      OUTPUTPATH_B3=$(find $FRW -type f -name "*_rhos_560.tif")
      OUTPUTPATH_B4=$(find $FRW -type f -name "*_rhos_665.tif")
      OUTPUTPATH_B5=$(find $FRW -type f -name "*_rhos_704.tif")
      OUTPUTPATH_B6=$(find $FRW -type f -name "*_rhos_740.tif")
      OUTPUTPATH_B7=$(find $FRW -type f -name "*_rhos_783.tif")
      OUTPUTPATH_B8=$(find $FRW -type f -name "*_rhos_833.tif")
      OUTPUTPATH_B8A=$(find $FRW -type f -name "*_rhos_865.tif")
      OUTPUTPATH_B11=$(find $FRW -type f -name "*_rhos_1614.tif")
      OUTPUTPATH_B12=$(find $FRW -type f -name "*_rhos_2202.tif")
    elif [ "$S2_SENSOR" == "S2B" ]
    then
      OUTPUTPATH_B1=$(find $FRW -type f -name "*_rhos_442.tif")
      OUTPUTPATH_B2=$(find $FRW -type f -name "*_rhos_492.tif")
      OUTPUTPATH_B3=$(find $FRW -type f -name "*_rhos_559.tif")
      OUTPUTPATH_B4=$(find $FRW -type f -name "*_rhos_665.tif")
      OUTPUTPATH_B5=$(find $FRW -type f -name "*_rhos_704.tif")
      OUTPUTPATH_B6=$(find $FRW -type f -name "*_rhos_739.tif")
      OUTPUTPATH_B7=$(find $FRW -type f -name "*_rhos_780.tif")
      OUTPUTPATH_B8=$(find $FRW -type f -name "*_rhos_833.tif")
      OUTPUTPATH_B8A=$(find $FRW -type f -name "*_rhos_864.tif")
      OUTPUTPATH_B11=$(find $FRW -type f -name "*_rhos_1610.tif")
      OUTPUTPATH_B12=$(find $FRW -type f -name "*_rhos_2186.tif")
    fi

    OUTPUT_B_VRT="${BNAME}_L2A_${ALGORITHM}_Rhow.vrt"
  
    # convert to LZW compressed GeoTIFF
    gdal_translate -q -of GTiff -ot UInt16 -b 1 -a_nodata 65535 -a_scale 0.0001 -a_offset 0 -co "COMPRESS=LZW" -mo "ALGORITHM=${ALGORITHM}" -mo "SUN_GLINT_CORRECTION=True" ${OUTPUTPATH_B1} ${BNAME}_L2A_${ALGORITHM}_Rhow_B1.tif
    gdal_translate -q -of GTiff -ot UInt16 -b 1 -a_nodata 65535 -a_scale 0.0001 -a_offset 0 -co "COMPRESS=LZW" -mo "ALGORITHM=${ALGORITHM}" -mo "SUN_GLINT_CORRECTION=True" ${OUTPUTPATH_B2} ${BNAME}_L2A_${ALGORITHM}_Rhow_B2.tif
    gdal_translate -q -of GTiff -ot UInt16 -b 1 -a_nodata 65535 -a_scale 0.0001 -a_offset 0 -co "COMPRESS=LZW" -mo "ALGORITHM=${ALGORITHM}" -mo "SUN_GLINT_CORRECTION=True" ${OUTPUTPATH_B3} ${BNAME}_L2A_${ALGORITHM}_Rhow_B3.tif
    gdal_translate -q -of GTiff -ot UInt16 -b 1 -a_nodata 65535 -a_scale 0.0001 -a_offset 0 -co "COMPRESS=LZW" -mo "ALGORITHM=${ALGORITHM}" -mo "SUN_GLINT_CORRECTION=True" ${OUTPUTPATH_B4} ${BNAME}_L2A_${ALGORITHM}_Rhow_B4.tif
    gdal_translate -q -of GTiff -ot UInt16 -b 1 -a_nodata 65535 -a_scale 0.0001 -a_offset 0 -co "COMPRESS=LZW" -mo "ALGORITHM=${ALGORITHM}" -mo "SUN_GLINT_CORRECTION=True" ${OUTPUTPATH_B5} ${BNAME}_L2A_${ALGORITHM}_Rhow_B5.tif
    gdal_translate -q -of GTiff -ot UInt16 -b 1 -a_nodata 65535 -a_scale 0.0001 -a_offset 0 -co "COMPRESS=LZW" -mo "ALGORITHM=${ALGORITHM}" -mo "SUN_GLINT_CORRECTION=True" ${OUTPUTPATH_B6} ${BNAME}_L2A_${ALGORITHM}_Rhow_B6.tif
    gdal_translate -q -of GTiff -ot UInt16 -b 1 -a_nodata 65535 -a_scale 0.0001 -a_offset 0 -co "COMPRESS=LZW" -mo "ALGORITHM=${ALGORITHM}" -mo "SUN_GLINT_CORRECTION=True" ${OUTPUTPATH_B7} ${BNAME}_L2A_${ALGORITHM}_Rhow_B7.tif
    gdal_translate -q -of GTiff -ot UInt16 -b 1 -a_nodata 65535 -a_scale 0.0001 -a_offset 0 -co "COMPRESS=LZW" -mo "ALGORITHM=${ALGORITHM}" -mo "SUN_GLINT_CORRECTION=True" ${OUTPUTPATH_B8} ${BNAME}_L2A_${ALGORITHM}_Rhow_B8.tif
    gdal_translate -q -of GTiff -ot UInt16 -b 1 -a_nodata 65535 -a_scale 0.0001 -a_offset 0 -co "COMPRESS=LZW" -mo "ALGORITHM=${ALGORITHM}" -mo "SUN_GLINT_CORRECTION=True" ${OUTPUTPATH_B8A} ${BNAME}_L2A_${ALGORITHM}_Rhow_B8A.tif
    gdal_translate -q -of GTiff -ot UInt16 -b 1 -a_nodata 65535 -a_scale 0.0001 -a_offset 0 -co "COMPRESS=LZW" -mo "ALGORITHM=${ALGORITHM}" -mo "SUN_GLINT_CORRECTION=True" ${OUTPUTPATH_B11} ${BNAME}_L2A_${ALGORITHM}_Rhow_B11.tif
    gdal_translate -q -of GTiff -ot UInt16 -b 1 -a_nodata 65535 -a_scale 0.0001 -a_offset 0 -co "COMPRESS=LZW" -mo "ALGORITHM=${ALGORITHM}" -mo "SUN_GLINT_CORRECTION=True" ${OUTPUTPATH_B12} ${BNAME}_L2A_${ALGORITHM}_Rhow_B12.tif
  
    # create virtual raster stack
    gdalbuildvrt -q -separate ${OUTPUT_B_VRT} ${BNAME}_L2A_${ALGORITHM}_Rhow_B1.tif ${BNAME}_L2A_${ALGORITHM}_Rhow_B2.tif ${BNAME}_L2A_${ALGORITHM}_Rhow_B3.tif ${BNAME}_L2A_${ALGORITHM}_Rhow_B4.tif ${BNAME}_L2A_${ALGORITHM}_Rhow_B5.tif ${BNAME}_L2A_${ALGORITHM}_Rhow_B6.tif ${BNAME}_L2A_${ALGORITHM}_Rhow_B7.tif ${BNAME}_L2A_${ALGORITHM}_Rhow_B8.tif ${BNAME}_L2A_${ALGORITHM}_Rhow_B8A.tif ${BNAME}_L2A_${ALGORITHM}_Rhow_B11.tif ${BNAME}_L2A_${ALGORITHM}_Rhow_B12.tif
  
    # remove temporary files
    rm -rf $OUTPUTPATH_B1 $OUTPUTPATH_B2 $OUTPUTPATH_B3 $OUTPUTPATH_B4 $OUTPUTPATH_B5 $OUTPUTPATH_B6 $OUTPUTPATH_B7 $OUTPUTPATH_B8 $OUTPUTPATH_B8A $OUTPUTPATH_B11 $OUTPUTPATH_B12
  
  fi
  
  # remove temporary files
  rm -rf ${L1C_NAME}
  find $FRW -type f -name "S2*_MSI_*.tif" ! -name "S2*_MSI_*_L2W_l2_flags.tif" -exec rm -rf {} \;
  find $FRW -type f -name "S2*_MSI_*.png" -exec rm -rf {} \;
  find $FRW -type f -name "S2*_MSI_*L1R.nc" -exec rm -rf {} \;
  
  # remove also part of the results to avoid large disk usage
  if [ ! "$KEEP" == "TRUE" ]
  then
    find $FRW -type f -name "S2*_MSI_*L2R.nc" -exec rm -rf {} \;
    find $FRW -type f -name "S2*_MSI_*L2W.nc" -exec rm -rf {} \;
    find $FRW -type f -name "S2*_MSI_*_L2W_l2_flags.tif" -exec rm -rf {} \;
    find $FRW -type f -name "*.txt" -exec rm -rf {} \;
    find $FRW -type f -name "*.cfg" -exec rm -rf {} \;
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


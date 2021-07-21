#!/bin/env bash

#######################################################
#
# Script Name: WaterColor_orchestrator.sh
# Version: 0.5.1
#
# Author: Federico Filipponi
# Date : 09.06.2021
#
# Copyright name: CC BY-NC-SA
# License: GPLv3
#
# Purpose: Estimate water color bio-geophysical parameters
#
# Description: 
# Usage: WaterColor_orchestrator.sh -c -a -k -i -r -q 20 -o /repository/dev/hm-wp6000/ff/river_color/test03 -l /repository/dev/hm-wp6000/ff/river_color/auxiliary_files/S2_river_color_comparison_list_test.txt -p /repository/dev/hm-wp6000/ff/river_color/auxiliary_files/Pressure_data_Po_20190508.csv -w /dati/workspace/f.filipponi
#
#######################################################

### to be done
# - aggiungi rimozione parent cartella workingdir (es. '/ssd/workspace/f.filipponi/T33SWB') se non ci sono dentro file (ma cartelle dell'anno es. '2020' possono esserci)

# Set Help function
Help()
{
  # Display command help
  echo "Usage : WaterColor_orchestrator.sh [Options] -f S2A_20210608.zip -o /space/output"
  echo ""
  echo "Options:"
  echo "    -a             Set algorithm (must be one of the followings: 'C2RCC', 'ACOLITE')"
  echo "    -c             Calibration parameters file (optional)"
  echo "    -f <file>      Input file"
  echo "    -g             Perform sun glint correction (optional, only supported in 'ACOLITE' algorithm)"
  echo "    -h             Help information for the operator"
  echo "    -k             Keep intermediate products (optional)"
  echo "    -i             Keep IOPs intermediate products (optional)"
  echo "    -l <file>      Input file list"
  echo "    -o <output>    Output file name"
  echo "    -p             Pressure data (optional)"
  echo "    -q <cores>     Number of cores to be used (optional)"
  echo "    -r             Keep Rhow intermediate products (optional)"
  echo "    -u             Output uncertainties (optional)"
  echo "    -v             Verbose mode"
  echo "    -w <folder>    Set temporary working directory (optional)"
  # echo ""
  # echo "  WaterColor orchestrator 0.5.1, GPL v3, CC BY-NC-SA 2018-2021 Federico Filipponi"
  # echo "  This is free software and comes with ABSOLUTELY NO WARRANTY"
}

# set default options


# get options
while getopts ":a:c:f:l:o:p:q:w:aghikruv" opt; do
  case $opt in
    f)
      FILE=$OPTARG
      ;;
    l)
      FILE_LIST=$OPTARG
      ;;
    p)
      PRESSURE_DATA=$OPTARG
      ;;
    c)
      CALIBRATED_PARAM=$OPTARG
      ;;
    o)
      OUTPUTDIR=$OPTARG
      ;;
    w)
      WORKINGDIR=$OPTARG
      ;;
    a)
      ALGORITHM=$OPTARG
      ;;
    q)
      CORES=$OPTARG
      ;;
    g)
      GLINT="TRUE"
      ;;
    i)
      IOP="TRUE"
      ;;
    r)
      RHOW="TRUE"
      ;;
    u)
      UNCERTAINTY="TRUE"
      ;;
    k)
      KEEP="TRUE"
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
    :a:c:f:l:o:p:q:w:)
      echo "Option -$OPTARG requires an argument." >&2
      exit 1
      ;;
  esac
done

#########################################
# check input arguments
# echo $OUTPUTDIR $FILE $FILE_LIST $WORKINGDIR $CORES

if [ $# -eq 0 ]
then
  Help
  exit 1
fi

if [ -z $ALGORITHM ]
then
  echo "Error: One retrieval algorithm should be selected among 'ACOLITE', 'C2RCC', 'C2X', 'C2XC'." >&2
  exit 1
fi

if [ ! "$ALGORITHM" == "ACOLITE" ] && [ ! "$ALGORITHM" == "C2RCC" ] && [ ! "$ALGORITHM" == "C2X" ] && [ ! "$ALGORITHM" == "C2XC" ]
then
  echo "Error: One retrieval algorithm should be selected among 'ACOLITE', 'C2RCC', 'C2X', 'C2XC'." >&2
  exit 1
fi

if [ -z $OUTPUTDIR ]
then
  echo "Error: Output path not set using the '-o' argument." >&2
  exit 1
fi

if [ -z $FILE_LIST ] && [ -z $FILE ]
then
  echo "Error: Provide one input file using the '-f' argument or alternatively a txt file containing a list of input files using '-l' argument." >&2
  exit 1
fi

if [ ! -z $FILE_LIST ] && [ ! -z $FILE ]
then
  echo "Error: Both input file and input file list found. Provide one input file using the '-f' argument or alternatively a txt file containing a list of input files using '-l' argument." >&2
  exit 1
fi

if [ ! -f $FILE_LIST ] && [ ! -z $FILE_LIST ]
then
  echo "Error: File list set using the '-l' argument does not exists." >&2
  exit 1
fi
if [ ! -f $FILE ] && [ ! -z $FILE ]
then
  echo "Error: File set using the '-f' argument does not exists." >&2
  exit 1
fi
if [ ! -z $OUTPUTDIR ]
then
  OUTPUTDIR=${OUTPUTDIR%%/}
  # check if user has write permissions
  if [ -d $OUTPUTDIR ] && [ ! -w $OUTPUTDIR ]
  then
    echo "Error: User does not have write permissions in output directory: ${OUTPUTDIR}." >&2
    exit 1
  fi
  mkdir -p ${OUTPUTDIR}
fi

if [ "$ALGORITHM" == "ACOLITE" ]
then
  if [ "$UNCERTAINTY" == "TRUE" ]
  then
    echo "Warning: uncertainty measure not available for algorithm 'ACOLITE'." >&2
  fi
  if [ "$IOP" == "TRUE" ]
  then
    echo "Warning: intermediate IOPs not available for algorithm 'ACOLITE'." >&2
  fi
else
  if [ "$GLINT" == "TRUE" ]
  then
    echo "Warning: sun glint correction only available for algorithm 'ACOLITE'." >&2
  fi
fi

if [ ! -z $WORKINGDIR ]
then
  WORKINGDIR=${WORKINGDIR%%/}
  # check if user has write permissions
  if [ -d $WORKINGDIR ] && [ ! -w $WORKINGDIR ]
  then
    echo "Error: User does not have write permissions in working directory: ${WORKINGDIR}." >&2
    exit 1
  fi
fi

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

# set environmental variables
PROCESSOR_HOME="$( cd "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
export PROCESSOR_HOME

# check GDAL version
GDAL_VERSION=$(gdalinfo --version | sed -n 's/,.*//p' | sed 's/GDAL //')
GDAL_VERSION=${GDAL_VERSION:0:1}
GDAL_VERSION=$((GDAL_VERSION + 0))
if [[ $GDAL_VERSION -lt 3 ]]
then
  echo "Error: GDAL version >= 3 is required." >&2
  exit 1
fi

# make 'acolite' alias work in non interactive shell
shopt -s expand_aliases
source /etc/bashrc

# if [ "$ALGORITHM" == "ACOLITE" ]
# then
#   if [[ ! -x $(command -v acolite) ]]
#   then
#     echo "Error: ACOLITE is not installed." >&2
#     exit 1
#   fi
# else
#     if [[ ! -x $(command -v gpt) ]]
#     then
#       echo "Error: SNAP 'gpt' is not installed." >&2
#     exit 1
#   fi
# fi

# add flags from arguments
ALG_ARGS=""
if [ "$KEEP" == "TRUE" ]
then
  ALG_ARGS="${ALG_ARGS} -k"
fi
if [ "$RHOW" == "TRUE" ]
then
  ALG_ARGS="${ALG_ARGS} -r"
fi
if [ "$VERBOSE" == "TRUE" ]
then
  ALG_ARGS="${ALG_ARGS} -v"
fi
if [ ! -z "$WORKINGDIR" ]
then
  ALG_ARGS="${ALG_ARGS} -w ${WORKINGDIR}"
fi
if [ -n "$PRESSURE_DATA" ]
then
  if [ -f $PRESSURE_DATA ]
  then
    ALG_ARGS="${ALG_ARGS} -p ${PRESSURE_DATA}"
  fi
fi
if [ -n "$CALIBRATED_PARAM" ]
then
  if [ -f $CALIBRATED_PARAM ]
  then
    ALG_ARGS="${ALG_ARGS} -c ${CALIBRATED_PARAM}"
  fi
fi

# set extra arguments for specific algorithm
if [ "$ALGORITHM" == "ACOLITE" ]
then
  ALG_BIN_SUFFIX="acolite"
  if [ "$GLINT" == "TRUE" ]
  then
    ALG_ARGS="${ALG_ARGS} -g"
  fi

else

  ALG_BIN_SUFFIX="C2RCC"
  ALG_ARGS="${ALG_ARGS} -a ${ALGORITHM}"
  if [ ! -z $CORES ]
  then
    ALG_ARGS="${ALG_ARGS} -q ${CORES}"
  fi
  if [ "$IOP" == "TRUE" ]
  then
    ALG_ARGS="${ALG_ARGS} -i"
  fi
  if [ "$UNCERTAINTY" == "TRUE" ]
  then
    ALG_ARGS="${ALG_ARGS} -u"
  fi

fi

# get process ID 'PID'
BASH_PID=$$

# get processing date
BASH_DATE=$(date --utc +%Y%m%d_%H%M%SZ)

# set log file path
LOG_FILE="${OUTPUTDIR}/WaterColor_${BASH_DATE}_${BASH_PID}_${ALGORITHM}.log.txt"

if [ ! -z $FILE ] && [ -f $FILE ]
then
  echo "$FILE" > ${OUTPUTDIR}/WaterColor_${BASH_DATE}_${BASH_PID}_${ALGORITHM}_file_list.txt
  FILE_LIST="${OUTPUTDIR}/WaterColor_${BASH_DATE}_${BASH_PID}_${ALGORITHM}_file_list.txt"
  TMP_FILE_LIST="TRUE"
fi

echo "###########################################################################################################"
echo "Water color processor - Process Earth Observation data using '${ALGORITHM}' algorithm - v0.5.1"
if [ "$VERBOSE" == "TRUE" ] && [[ $CORES -gt 1 ]]
then
  echo "Number of cores used for processing is: '${CORES}'"
fi
echo ""

#########################################
((
# time starting
START_CYCLE="$(date +%s%N)"

#########
# for debug
# FILE_LIST="/repository/dev/hm-wp6000/ff/river_color/auxiliary_files/S2_river_color_comparison_list_test.txt"
# OUTPUTDIR="/repository/dev/hm-wp6000/ff/river_color/test01"
# WORKINGDIR="/dati/workspace/f.filipponi"
# PRESSURE_DATA="/space/filipfe_data/me/arpav/lago_santa_croce/auxiliary_files/insitu/Pressure_data.csv"
# CALIBRATED_PARAM="/repository/dev/C2RCC_calibration.txt"
# ACOLITE="FALSE"
# C2RCC="TRUE"
# KEEP="TRUE"
# IOP="TRUE"
# RRS="TRUE"
# CORES=20
# UNCERTAINTY="TRUE"
# FILE="/repository/lavisam/hub/sentinel_hub/sentinel2/l1c/T32TPQ/2016/S2A_MSIL1C_20160701T102022_N0204_R065_T32TPQ_20160701T102057.zip"
# FILE="/repository/dev/hm-wp6000/ff/river_color/input/L8/L1T/LC08_L1TP_193029_20160701_20170323_01_T1.tar.gz"

# extract data and process
for FILE in $(< $FILE_LIST)
do

  RUN_PROCESS="TRUE"

  #########################################
  # Identify satellite sensor

  # extract file basename
  BSNAME=$(basename $FILE )
  SNAME=${BSNAME:0:2}


  if [ "$SNAME" != "S2" ] && [ "$SNAME" != "S3" ] && [ "$SNAME" != "LC" ] && [ "$SNAME" != "LE" ] && [ "$SNAME" != "LT" ]
  then
    echo "Error: Data not supported (filename must start with 'S2' for Sentinel-2 MSI, 'S3' for Sentinel-3 OLCI, 'LC08' for Landsat-8 OLI, 'LT05' for Landsat-5 TM or 'LC07' for Landsat-7 ETM)" >&2
    RUN_PROCESS="FALSE"

    else
  
    if [ "$SNAME" == "S2" ]
    then
      # echo "Data sensed by Sentinel-2 MSI"
      SENSOR="MSI"
    elif [ "$SNAME" == "LC" ]
    then
      # echo "Data sensed by Landsat-8 OLI"
      SENSOR="OLI"
    elif [ "$SNAME" == "LE" ]
    then
      # echo "Data sensed by Landsat-7 ETM"
      SENSOR="ETM"
    elif [ "$SNAME" == "LT" ]
    then
      echo "Data sensed by Landsat-5 TM"
      SENSOR="TM_"
    elif [ "$SNAME" == "an" ]
    then
      echo "Data sensed by PlanetScope"
      SENSOR="PS_"
    fi
  fi

  # check compatibility with the selected algorithm
  if [ ! "$ALGORITHM" == "ACOLITE" ]
  then
    if [ "$SNAME" == "LE" ] || [ "$SNAME" == "LT" ] || [ "$SNAME" == "an" ]
    then
      echo "Error: Data not supported for the selected algorithm ${ALGORITHM}" >&2
      RUN_PROCESS="FALSE"
    fi
  fi

  if [ "$RUN_PROCESS" == "TRUE" ]
  then

    # process 
    ${PROCESSOR_HOME}/bin/${SNAME}_${ALG_BIN_SUFFIX}.sh -f ${FILE} -o ${OUTPUTDIR}${ALG_ARGS}

  fi
done

# remove generated file list file
if [ "$TMP_FILE_LIST" == "TRUE" ]
then
  rm -rf ${FILE_LIST}
fi

# compute overall computation time
# get time interval in nanoseconds
T="$(($(date +%s%N)-START_CYCLE))"
# Seconds
S="$((T/1000000000))"
# Milliseconds
M="$((T%1000000000/1000000))"

echo 
echo "Processing of file finished at: $(date)" >&2
printf "Elapsed time: %02d:%02d:%02d:%02d.%03d\n" "$((S/86400))" "$((S/3600%24))" "$((S/60%60))" "$((S%60))" "${M}"
) 2>&1 ) |& tee ${LOG_FILE}


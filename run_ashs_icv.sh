#!/bin/bash -e

module load c3d/20191022
module load ashs

scriptPath=$(readlink -e "$0")
scriptDir=$(dirname "${scriptPath}")

# Default atlas for 3T T1w
icvAtlas="${ASHS_ROOT}/atlases/ICV_3TT1MRI_atlas"

if [[ ! -f "${ASHS_ROOT}/bin/ashs_main.sh" ]]; then
  echo "Cannot locate ASHS executables at ${ASHS_ROOT}/bin"
  exit 1
fi

# Variables used in functions
inputT1w=""
inputT1wBasename=""
inputT1wDirname=""
inputT1wFileRoot=""
outputDir=""

# Submit to queue, if 1 call ashs_main with -l
submitToQueue=0

# Leave at 1 if submitting jobs, otherwise set to num procs
greedyThreads=1

# cleanup tmp dir
cleanup=1

# trim neck
trimNeck=1

##############################################

function usage()
{
    echo "
    $0 -g <t1w> -o <output dir> [-l <(0)|1>] [-c <(1)|0>] [-t <(1)|0>] [-I <ICV atlas>]
    $0 -h for extended help.
    "
}

function help()
{
    usage
    echo "

    This script is a simplified wrapper for ASHS ICVF estimation. See the usage for ashs_main.sh for more options.

    The script requires the variable ASHS_ROOT, where \${ASHS_ROOT}/bin/ashs_main.sh exists.

    Required args:

      -g : Head T1w image.

      -o : Output directory.


    Options:

      -c : Cleanup working directory (default = $cleanup).

      -l : Parallel execution with LSF (default = $submitToQueue), for faster segmentation of a single session. If
           processing many sessions, it's more efficient to run without this option.

      -t : Trim neck from the input T1w image using the trim_neck.sh script (default = $trimNeck).


    Custom atlas options:

      -I : atlas for ICV estimation (default = $icvAtlas).

      The default atlas is defined on 3T data from the Penn Memory Center. You may use custom atlases for other
      data sets. See the ASHS website for details of atlas construction.

    Referencing:

    Please cite this paper when using ASHS results in published research

      Yushkevich PA, Pluta J, Wang H, Ding SL, Xie L, Gertje E, Mancuso L, Kliot D, Das SR and Wolk DA,
      \"Automated Volumetry and Regional Thickness Analysis of Hippocampal Subfields and Medial Temporal
      Cortical Structures in Mild Cognitive Impairment\", Human Brain Mapping, 2014, 36(1), 258-287.
      http://www.ncbi.nlm.nih.gov/pubmed/25181316

    Further information:

      ASHS website: https://sites.google.com/site/hipposubfields/
    "
}

function options()
{
  if [[ $# -eq 0 ]]; then
    usage
    exit 1
  fi

  while getopts "I:c:g:l:o:t:h" opt; do
    case $opt in
      I) icvAtlas=$(readlink -m "$OPTARG");;
      c) cleanup=$OPTARG;;
      g) inputT1w=$(readlink -m "$OPTARG");;
      l) submitToQueue=$OPTARG;;
      o) outputDir=$(readlink -m "$OPTARG");;
      t) trimNeck=$OPTARG;;
      h) help; exit 1;;
      \?) echo "Unknown option $OPTARG"; exit 2;;
      :) echo "Option $OPTARG requires an argument"; exit 2;;
    esac
  done

  # Check required args
  if [[ ! -f "$inputT1w" ]]; then
    echo "T1w image not found: $inputT1w"
    exit 1
  fi

  inputT1wBasename=$(basename "$inputT1w")
  inputT1wDirname=$(dirname "$inputT1w")

  # Trim neck can change input, so don't allow input directory to be output directory
  if [[ "${outputDir}" == "${inputT1wDirname}" ]]; then
    echo "Output directory cannot be the same as the input directory"
    exit 1
  fi

  if [[ "$inputT1wBasename" =~ .nii(.gz)?$ ]]; then
    extension=${BASH_REMATCH[0]}
    inputT1wFileRoot=${inputT1wBasename%${extension}}
  else
    echo "Input data must be in NIFTI-1 format"
    exit 1
  fi
}

function ICVSeg()
{
  queueOpt=""

  if [[ $submitToQueue -eq 1 ]]; then
    queueOpt="-l"
  fi

  ${ASHS_ROOT}/bin/ashs_main.sh \
    -a $icvAtlas -d -T -I $inputT1wFileRoot -g $segT1w \
    -f $segT1w \
    -s 1-7 \
    -B \
    -t ${greedyThreads} \
    -w ${jobTmpDir}/ICVSeg $queueOpt
}

function Summarize()
{
  cp ${jobTmpDir}/ICVSeg/final/${inputT1wFileRoot}_left_lfseg_corr_nogray.nii.gz \
     ${outputDir}/${inputT1wFileRoot}_ICVSeg.nii.gz

  cp ${jobTmpDir}/ICVSeg/final/${inputT1wFileRoot}_left_corr_nogray_volumes.txt \
     ${outputDir}/${inputT1wFileRoot}_ICVSeg_volumes.txt

  mkdir ${outputDir}/qa
  cp -r ${jobTmpDir}/ICVSeg/qa ${outputDir}/qa/ICV_qa
}

######################################################

options $@

# Check we're in a bsub job
if [[ -z "${LSB_DJOB_NUMPROC}" ]]; then
    echo "Script must be run from within an LSB job"
    exit 1
fi

if [[ $submitToQueue -eq 0 ]]; then
  greedyThreads=${LSB_DJOB_NUMPROC}
fi

# Need this or NLMDenoise will attempt to use all the cores
export ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS=${LSB_DJOB_NUMPROC}

# make output directory
mkdir -p ${outputDir}

# Make tmp directory
jobTmpDir=$( mktemp -d -p /scratch ashs.${LSB_JOBID}.XXXXXXX.tmpdir )

if [[ ! -d "$jobTmpDir" ]]; then
    echo "Could not create job temp dir ${jobTmpDir}"
    exit 1
fi

# This is what gets used in the segmentation call
segT1w=${outputDir}/${inputT1wBasename}

# Optionally trim neck of input
if [[ $trimNeck -gt 0 ]]; then
  echo "Preprocessing: Trim neck from T1w image"

  mkdir ${jobTmpDir}/neckTrim

  ${scriptDir}/trim_neck.sh -d -c 10 -w ${jobTmpDir}/neckTrim $inputT1w ${segT1w}
  echo "Preprocessing: Done!"
else
  cp $inputT1w ${segT1w}
fi

# perform ICV segmentation
echo "Step 1/2: Performing intracranial volume segmentation"
ICVSeg
echo "Step 1/2: Done!"

# reorganize and summarize the result
echo "Step 2/2: Reorganize output and summarize the result"
Summarize
echo "Step 2/2: Done!"

if [[ $cleanup -gt 0 ]]; then
  rm -rf ${jobTmpDir}/ICVSeg ${jobTmpDir}/neckTrim
  rmdir ${jobTmpDir}
else
  echo "Not cleaning up working directory ${jobTmpDir}"
fi

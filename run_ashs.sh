#!/bin/bash -e

module load c3d/20191022
module load ashs

scriptPath=$(readlink -e "$0")
scriptDir=$(dirname "${scriptPath}")

# Default atlases
mtlT1wAtlas="${ASHS_ROOT}/atlases/MTL_3TT1MRI_PMC_atlas"
mtlT2wAtlas="${ASHS_ROOT}/atlases/MTL_3TT2MRI_ABC_prisma_atlas"
# ICV always done on T1w
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
inputT2w=""
inputT2wBasename=""
inputT2wDirname=""
inputT2wFileRoot=""
outputDir=""
inputTransform=""

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
    $0 -g <t1w> -o <output dir> [-f <temporal lobe T2w>] [-l <(0)|1>] [-c <(1)|0>] [-m <t2w to t1w transform>]
       [-t <(1)/0>] [-I <ICV atlas>] [-M <MTL T2w atlas>] [-T <MTL T1w atlas>]

    $0 -h for extended help.
    "
}

function help()
{
    usage
    echo "

    This script is a simplified wrapper for ASHS. See the usage for ashs_main.sh for more options.

    The script requires the variable ASHS_ROOT, where \${ASHS_ROOT}/bin/ashs_main.sh exists.

    Before running ASHS, check that your data is correctly formatted, see

    https://sites.google.com/site/hipposubfields/tutorial

    The stages in this script are:

    1. MTL segmentation. If present, the T2w high-resolution scan is used to segment MTL structures. If there is no T2w
       input, the T1w image is used instead.

    2. ICV segmentation. The whole-head T1w is used to esimate ICV.

    3. Statistics and QA.


    Required args:

      -g : Head T1w image.

      -o : Output directory.


    Options:

      -c : Cleanup working directory (default = $cleanup).

      -f : T2w MTL image. This is a specialized image, described in the ASHS documentation as: \"oblique coronal,
           oriented along the main axis of the hippocampus. It should have high in-plane resolution (0.4mmx0.4mm)
           which is typically achieved at the cost of higher slice thickness (1.0-3.0mm). Importantly, the slice
           direction (anterior-posterior direction) should be the last dimension of the image.\"

           The T2w and T1w images should be in the same physical space. This can be verified by loading both into
           ITK-SNAP. See the ASHS website for more details.

      -l : Parallel execution with LSF (default = $submitToQueue).

      -m : Affine transform aligning MTL to T1w. By default, this is computed
           automatically. Use this option to use a pre-defined transform instead. The transform should be computed
           with greedy, using the T2w as the fixed image and the T1w as the moving image.

      -t : Trim neck from the input T1w image using the trim_neck.sh script (default = $trimNeck).


    Custom atlas options:

      -F : MTL T2w atlas (default = $mtlT2wAtlas).
      -G : MTL T1w atlas (default = $mtlT1wAtlas).
      -I : T1w atlas for ICV estimation (default = $icvAtlas).

      The default atlases are defined on 3T data from the Penn Memory Center. You may use custom atlases for other
      data sets. See the ASHS website for details of atlas construction.

      The atlas label definitions, in ITK-SNAP format, are in

        atlas_dir/snap


    Referencing:

    Please cite this paper in reference to ASHS software and the 3T T2w MTL atlas:

      Yushkevich PA, Pluta J, Wang H, Ding SL, Xie L, Gertje E, Mancuso L, Kliot D, Das SR and Wolk DA,
      \"Automated Volumetry and Regional Thickness Analysis of Hippocampal Subfields and Medial Temporal
      Cortical Structures in Mild Cognitive Impairment\", Human Brain Mapping, 2014, 36(1), 258-287.
      http://www.ncbi.nlm.nih.gov/pubmed/25181316

      If using the T1w MTL atlas, please also cite

      \"Xie L, Wisse LEM, Das SR, Wang H, Wolk DA, Manjón JV, et al. Accounting for the Confound of Meninges
      in Segmenting Entorhinal and Perirhinal Cortices in T1-Weighted MRI\".
      Med Image Comput Comput Assist Interv 2016;9901:564-71.
      https://pubmed.ncbi.nlm.nih.gov/28752156/


    Further information:

      This script is written by Philip Cook and Long Xie.

      ASHS website: https://sites.google.com/site/hipposubfields/
    "
}

function options()
{

  if [[ $# -eq 0 ]]; then
    usage
    exit 1
  fi

  while getopts "I:M:T:c:f:g:l:m:o:t:h" opt; do
    case $opt in
      F) mtlT2wAtlas=$(readlink -m "$OPTARG");;
      G) mtlT1wAtlas=$(readlink -m "$OPTARG");;
      I) icvAtlas=$(readlink -m "$OPTARG");;
      c) cleanup=$OPTARG;;
      f) inputT2w=$(readlink -m "$OPTARG");;
      g) inputT1w=$(readlink -m "$OPTARG");;
      l) submitToQueue=$OPTARG;;
      m) inputTransform=$(readlink -m "$OPTARG");;
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

  if [[ -n "$inputT2w" ]] && [[ ! -f "$inputT2w" ]]; then
    echo "T2w image not found: $inputT2w"
    exit 1
  fi

  if [[ -n "$inputTransform" ]] && [[ ! -f "$inputTransform" ]]; then
    echo "MTL to T1w transform not found: $inputTransform"
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

  if [[ -f "$inputT2w" ]]; then
    inputT2wBasename=$(basename "$inputT2w")
    inputT2wDirname=$(dirname "$inputT2w")
    if [[ "$inputT2wBasename" =~ .nii(.gz)?$ ]]; then
      extension=${BASH_REMATCH[0]}
      inputT2wFileRoot=${inputT2wBasename%${extension}}
    else
      echo "Input data must be in NIFTI-1 format"
      exit 1
    fi
  fi

}

function MTLSeg()
{
  # If no T2w, use T1w for both inputs
  segT2w=$inputT1w
  segAtlas=$mtlT1wAtlas

  mtlOutputFileRoot=$inputT1wFileRoot

  if [[ -f "${inputT2w}" ]]; then
    segT2w=$inputT2w
    segAtlas=$mtlT2wAtlas
    mtlOutputFileRoot=$inputT2wFileRoot
  fi

  transformOpt=""

  if [[ -f "${inputTransform}" ]]; then
    transformOpt="-m $inputTransform -M"
  fi

  queueOpt=""

  if [[ $submitToQueue -eq 1 ]]; then
    queueOpt="-l"
  fi

  ${ASHS_ROOT}/bin/ashs_main.sh \
    -a $segAtlas -d -T -I $mtlOutputFileRoot -g $inputT1w \
    -f $segT2w \
    -s 1-7 \
    -t ${greedyThreads} \
    -w ${jobTmpDir}/MTLSeg $transformOpt $queueOpt
}

function ICVSeg()
{

  queueOpt=""

  if [[ $submitToQueue -eq 1 ]]; then
    queueOpt="-l"
  fi

  ${ASHS_ROOT}/bin/ashs_main.sh \
    -a $icvAtlas -d -T -I $inputT1wFileRoot -g $inputT1w \
    -f $inputT1w \
    -s 1-7 \
    -B \
    -t ${greedyThreads} \
    -w ${jobTmpDir}/ICVSeg $queueOpt
}

function Summarize()
{

  mtlOutputFileRoot=$inputT1wFileRoot

  if [[ -f "${inputT2w}" ]]; then
    mtlOutputFileRoot=$inputT2wFileRoot
  fi

  cp ${jobTmpDir}/MTLSeg/tse.nii.gz \
     ${outputDir}/${mtlOutputFileRoot}_denoised_SR.nii.gz

  cp ${jobTmpDir}/MTLSeg/final/${mtlOutputFileRoot}_left_lfseg_heur.nii.gz \
     ${outputDir}/${mtlOutputFileRoot}_MTLSeg_left.nii.gz
  cp ${jobTmpDir}/MTLSeg/final/${mtlOutputFileRoot}_right_lfseg_heur.nii.gz \
     ${outputDir}/${mtlOutputFileRoot}_MTLSeg_right.nii.gz

  cp ${jobTmpDir}/MTLSeg/final/${mtlOutputFileRoot}_left_heur_volumes.txt \
     ${outputDir}/${mtlOutputFileRoot}_MTLSeg_left_volumes.txt
  cp ${jobTmpDir}/MTLSeg/final/${mtlOutputFileRoot}_right_heur_volumes.txt \
     ${outputDir}/${mtlOutputFileRoot}_MTLSeg_right_volumes.txt

  cp ${jobTmpDir}/ICVSeg/final/${inputT1wFileRoot}_left_lfseg_corr_nogray.nii.gz \
     ${outputDir}/${inputT1wFileRoot}_ICVSeg.nii.gz

  cp ${jobTmpDir}/ICVSeg/final/${inputT1wFileRoot}_left_corr_nogray_volumes.txt \
     ${outputDir}/${inputT1wFileRoot}_ICVSeg_volumes.txt

  mkdir ${outputDir}/qa
  cp -r ${jobTmpDir}/MTLSeg/qa ${outputDir}/qa/ASHST1_qa
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

# Optionally trim neck of input
if [[ $trimNeck -gt 0 ]]; then
  echo "Preprocessing: Trim neck from T1w image"

  mkdir ${jobTmpDir}/neckTrim

  ${scriptDir}/trim_neck.sh -d -c 10 -w ${jobTmpDir}/neckTrim $inputT1w ${outputDir}/${inputT1wBasename}
  echo "Preprocessing: Done!"
else
  cp $inputT1w ${outputDir}/${inputT1wBasename}
fi

if [[ -f ${inputT2w} ]]; then
    cp $inputT2w ${outputDir}/${inputT2wBasename}
fi


# perform MTL segmentation
echo "Step 1/3: Performing medial temporal lobe segmentation"
MTLSeg
echo "Step 1/3: Done!"

# perform ICV segmentation
echo "Step 2/3: Performing intracranial volume segmentation"
ICVSeg
echo "Step 2/3: Done!"

# reorganize and summarize the result
echo "Step 3/3: Reorganize output and summarize the result"
Summarize
echo "Step 3/3: Done!"

if [[ $cleanup -gt 0 ]]; then
  rm -rf ${jobTmpDir}/MTLSeg ${jobTmpDir}/ICVSeg ${jobTmpDir}/neckTrim
  rmdir ${jobTmpDir}
else
  echo "Not cleaning up working directory ${jobTmpDir}"
fi

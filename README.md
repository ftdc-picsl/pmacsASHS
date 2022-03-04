# pmacsASHS

Wrapper for ASHS on the PMACS LPC.

The wrapper script `run_ashs.sh` is adapted from a CFN cluster script provided by Long
Xie. By default, it uses 3T atlases for T1w and T2w MRI from the PMC. The MTL atlas
modality is automatically selected based on the input data.

For more information, see the help for the script and the [ASHS
website](https://sites.google.com/site/hipposubfields).


## Reference

For ASHS itself and the included 3T atlases:

Yushkevich PA, Pluta J, Wang H, Ding SL, Xie L, Gertje E, Mancuso L, Kliot D, Das SR and
Wolk DA, "Automated Volumetry and Regional Thickness Analysis of Hippocampal Subfields
_and Medial Temporal Cortical Structures in Mild Cognitive Impairment", _Human Brain
Mapping_, 2014, 36(1), 258-287. http://www.ncbi.nlm.nih.gov/pubmed/25181316
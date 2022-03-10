# pmacsASHS

Wrapper for ASHS on the PMACS LPC.

The wrapper script `run_ashs.sh` is adapted from a CFN cluster script provided by Long
Xie. By default, it uses 3T atlases for T1w and T2w MRI from the PMC. The MTL atlas
modality is automatically selected based on the input data.

For more information, see the help for the script and the [ASHS
website](https://sites.google.com/view/ashs-dox).


## Reference

For ASHS itself and the 3T T2w MTL atlas:

Yushkevich PA, Pluta JB, Wang H, Xie L, Ding S-L, Gertje EC, et al. Automated volumetry
and regional thickness analysis of hippocampal subfields and medial temporal cortical
structures in mild cognitive impairment. Hum Brain Mapp 2015;36:258–87.
http://www.ncbi.nlm.nih.gov/pubmed/25181316

For the 3T T1w MTL atlas:

Xie L, Wisse LEM, Das SR, Wang H, Wolk DA, Manjón JV, et al. Accounting for the Confound
of Meninges in Segmenting Entorhinal and Perirhinal Cortices in T1-Weighted MRI. Med Image
Comput Comput Assist Interv 2016;9901:564–71. https://pubmed.ncbi.nlm.nih.gov/28752156/

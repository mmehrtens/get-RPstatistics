# get-RPstatistics.ps1
Powershell script to retrieve a summary of all existing Veeam  backup restore points

This script enumerates all existing restore points and creates 2 output files with following content 
  - **Veeam-RPs.csv**:
    a list of all restore points incl. type of backup,
    backup file size, creation time, compression and dedupe ratios,
    change rates (for incremental restore points only) and
    a few blocksize calculations (for object storage sizing assistance)
  - **Veeam-RPs-stats.csv**:
    average change and reduction rates per vm and job
    (separated for full and incremental restore points)

Contents of these files will also be displayed interactively via GridView
(can easily be disabled by commenting lines out at the end of this script file)


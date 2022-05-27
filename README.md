# get-RPstatistics.ps1
PowerShell script to retrieve a summary of all existing Veeam  backup restore points

This script enumerates all existing restore points and creates two output files in CSV format 
  - **_VBR-Servername_-RestorePoints.csv**:
    a list of all restore points incl. type of backup,
    backup file size, creation time, compression and dedupe ratios,
    change rates (for incremental restore points only) and
    a few blocksize calculations (for object storage sizing assistance)
  - **_VBR-Servername_-RestorePoints-statistics.csv**:
    backup volume, average change and reduction rates per vm and job
    (separated for full and incremental restore points)

Mandatory parameters:
  - ```-vbrServer``` = Veeam backup server name or IP to connect to

Optional parameters:
  - ```-suppressGridDisplay``` = don't show GridViews after processing


Requires [Veeam Powershell module].


<!-- referenced links -->
[Veeam PowerShell module]: https://helpcenter.veeam.com/docs/backup/powershell/getting_started.html

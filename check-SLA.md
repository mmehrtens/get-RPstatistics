# check-SLA.ps1

This script will read all the most recent restore points from all backup jobs of a single or multiple VBR servers. SLA compliance ratio (in percent) is calculated based on which percentage of the restore points have been created within the given backup window in comparison to the total number of restore points.

Requires [Veeam Powershell module].

> **Note:** If a VM within a particular job has NEVER been backed up successfully (i.e., no restore points exist for this VM at all), or if a job didn't run at least successfully once, this script will not be able report these as being 'outside of backup window' as it simply cannot process something that doesn't exist.

> **2nd Note:** If a restore point is newer than the backup window end time, it will be ignored and the next (older) restore point will be checked for backup window compliance instead.

## Parameters:
### Mandatory
- `vbrServer` = Veeam backup server name or IP to connect to (can be a pipelined value to process multiple VBR servers)
### Not mandatory
- `lookBackDays` = how many days should the script look back for the backup window start? (int, default `1` can be changed in `Param()`-section)
- `backupWindowStart` = at which time of day starts the backup window? (string in 24h format, default `"20:00"` can be changed in `Param()`-section)
- `backupWindowEnd` = at which time of day ends the backup window? (string in 24h format, default `"07:00"` can be changed in `Param()`-section)
- `displayGrid` = switch to display results in PS-GridViews (default = `$false`)
- `outputDir` = where to write the output files (folder must exist, otherwise defaulting to script folder)
- `Verbose` = write details about script steps to screen while executing (only for debugging, default = `$false`)

Backup window **start** will be calculated as follows:  
- Day  = today minus parameter `lookBackDays`
- Time = time of day set in parameter `backupWindowStart`

Backup window **end** will be calculated as follows:
- Day  = today, if `backupWindowEnd` is in the past; yesterday otherwise.
- Time = time of day set in parameter `backupWindowEnd`

Two output files will be created in the output folder:
1. CSV file containing most recent restore points with some details and whether they comply to backup window
2. CSV file containing single line summary of SLA compliance

[Back to overview](README.md)

<!-- referenced links -->
[Veeam PowerShell module]: https://helpcenter.veeam.com/docs/backup/powershell/getting_started.html

# Veeam Restore Point Statistics

Scripts to gather some statistics from existing [Veeam Backup & Replication] restore points.

1. [get-rpstatistics](get-rpstatistics.md)  
    Builds a CSV export of all existing restore points and creates a second CSV showing statistics about change rates, dedupe/compression rates, block sizes etc.

2. [check-SLA](check-SLA.md)  
    Checks if most recent restore points of all jobs have been created in a given backup window.

All scripts require [Veeam Powershell module].

<!-- referenced links -->
[Veeam Backup & Replication]: https://www.veeam.com/vm-backup-recovery-replication-software.html
[Veeam PowerShell module]: https://helpcenter.veeam.com/docs/backup/powershell/getting_started.html

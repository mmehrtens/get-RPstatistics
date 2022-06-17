# check-SLA.ps1
#
# This script will read all the most recent restore points from all backup jobs of a single or multiple VBR servers.
# SLA fulfillment ratio (in percent) is calculated based on which percentage of the restore points have been created
# within the given backup window in comparison to the total number of restore points.
#
# Note: If a VM within a particular job has NEVER been backed up successfully (i.e., no restore points exist for
#       this VM at all), or if a job didn't run at least successfully once, this script will not be able report these
#       as being 'outside of backup window' as it simply cannot process something that doesn't exist.
#
# Note: If a restore point is newer than the backup window end time, it will be ignored and the next (older) restore
#       point will be checked for backup window compliance instead.
#
# Requires module 'Veeam.Backup.PowerShell'
#
# Parameters:
#   -vbrServer [server] = Veeam backup server name or IP to connect to (can be a pipelined value to process multiple VBR servers)
#   -lookBackDays = how many days should the script look back for the backup window start? (default can be changed in Param()-section)
#   -backupWindowStart = at which time of day starts the backup window? (string in 24h format, default can be changed in Param()-section)
#   -backupWindowEnd = at which time of day ends the backup window? (string in 24h format, default can be changed in Param()-section)
#   -displayGrid = switch to display results in PS-GridViews (default = $false)
#   -outputDir = where to write the output files (folder must exist, otherwise defaulting to script folder)
#   -verbose = write details about script steps to screen while executing (only for debugging, default off)
# 
# Backup windows start will be calculated as follows:
#   Day  = today minus parameter 'lookBackDays'
#   Time = time of day set in parameter 'backupWindowStart'
# Backup windo end will be calculated as follows:
#   Day  = yesterday, if time in 'backupWindowEnd' is in the future; otherwise today
#   Time = time of day set in parameter 'backupWindowEnd'
# 
# Two output files will be created in the output folder:
#   1. CSV file containing most recent restore points with some details and whether they comply to backup window
#   2. CSV file containing single line summary of SLA compliance
#
# 2022.06.16 by M. Mehrtens
# -----------------------------------------------

# vbrServer passed as parameter (script will ask for credentials if there is no credentials file!)
Param(
    [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
        [string]$vbrServer,
    [Parameter(Mandatory=$false)]
        [int]$lookBackDays=1,
    [Parameter(Mandatory=$false)]
        [string]$backupWindowStart="20:00",
    [Parameter(Mandatory=$false)]
        [string]$backupWindowEnd="07:00",
    [Parameter(Mandatory=$false)]
        [switch]$displayGrid=$false,
    [Parameter(Mandatory=$false)]
        [string]$outputDir=""

)
# -----------------------------------------------


Begin {

    # calculate backup window start and stop times from parameters
    $now = Get-Date
    $intervalStart = [Datetime]("$($now.Year)" + "." + `
                                "$($now.Month)" + "." + `
                                "$($now.Day)" + " " + `
                                "$backupWindowStart")
    $intervalEnd   = [Datetime]("$($now.Year)" + "." + `
                                "$($now.Month)" + "." + `
                                "$($now.Day)" + " " + `
                                "$backupWindowEnd")
    
    # subtract $lookBackDays from backup window start time
    $intervalStart = $intervalStart.AddDays(- $lookBackDays)

    # if backup window end time lies in future, use end time of yesterday
    if($intervalEnd -gt $now) {
        $intervalEnd = $intervalEnd.AddDays(-1)
    }

    Write-Output "Backup window"
    Write-Output "  start: $intervalStart"
    Write-Output "    end: $intervalEnd"


    $jobTypesScope =  @("Backup",
                        "EndpointBackup",
                        "EpAgentBackup",
                        "EpAgentManagement",
                        "EPAgentPolicy")

    $jobBlockSizes   = [PSCustomobject]@{ kbBlockSize256  = 256 * 1024
                                        kbBlockSize512  = 512 * 1024
                                        kbBlockSize1024 = 1024 * 1024
                                        kbBlockSize4096 = 4096 * 1024
                                        kbBlockSize8192 = 8192 * 1024
                                        Automatic = "[Automatic]"
                                        }

    # helper function to format numbers as MB/GB/TB/etc.
    Function Format-Bytes {
        Param
        (
            [Parameter(
                ValueFromPipeline = $true
            )]
            [ValidateNotNullOrEmpty()]
            [float]$number
        )
        Begin{
            $sizes = 'kB','MB','GB','TB','PB'
        }
        Process {
            # New for loop
            for($x = 0; $x -lt $sizes.count; $x++){
                if ($number -lt "1$($sizes[$x])"){
                    if ($x -eq 0){
                        return "$number B"
                    } else {
                        $num = $number / "1$($sizes[$x-1])"
                        $num = "{0:N2}" -f $num
                        return "$num $($sizes[$x-1])"
                    }
                }
            }

        }
        End{}
    }

    # function to retrieve path of repository
    function get_backupfile_path($objRP) {

        $retval = $null
        $extent = $objRP.FindChainRepositories()

        if($extent) {
            if($extent.Type -iin ('Nfs', `
                                'CifsShare', `
                                'SanSnapshotOnly', `
                                'DDBoost', `
                                'HPStoreOnceIntegration', `
                                'AmazonS3External', `
                                'AzureStorageExternal') ) {
                $retval = "$($extent.FriendlyPath)"
            } else {
                $retval = "$($extent.Host.Name):$($extent.FriendlyPath)"
            }
        }
        return $retval
    }
}

Process {
    $Error.Clear()
    Write-Verbose "Backup Server: $vbrServer"
    # output files path/name prefix
    $outfilePrefix = "$($now.ToString("yyyy-MM-ddTHH-mm-ss"))-$($vbrServer)"
    

    # -----------------------------------------------
    if($outputDir -eq "") {
        $outputDir = $PSScriptRoot
    } elseif(-not (Test-Path -PathType Container $outputDir)) {
            $outputDir = $PSScriptRoot
    } else {
        $outputDir = $outputDir.TrimEnd("\")
    }
    # credential file for this server
    $credFile = "$PSScriptRoot\$vbrServer-creds.xml"
    # output file of restore points
    $outfileRP = "$outputDir\$outfilePrefix-RPs.csv"
    #output file for statistics
    $outfileStatistics = "$outputDir\$outfilePrefix-SLA.csv"

    Write-Progress -Activity "Connecting to $vbrServer" -Id 1

    # read credentials for vbr server authentication if file exists, otherwise ask for credentials and save them
    Disconnect-VBRServer -ErrorAction SilentlyContinue
    try {
            $myCreds = Import-Clixml -path $credFile
            Write-Verbose "Credentials read from ""$credFile."""
    } catch {
        Write-Verbose """$credFile"" not found, asking for credentials interactively."
        $myCreds = Get-Credential -Message "Credentials for $vbrServer"
        if($null -ne $myCreds) {
            $myCreds | Export-CliXml -Path $credFile | Out-Null
            Write-Verbose "Credentials written to ""$credFile."""
        } else {
            Write-Verbose "No Credentials, aborting."
            return
        }
    }

    # establish connection to vbr server
    try {
        Connect-VBRServer -Server $vbrServer -Credential $myCreds
        Write-Verbose "Connection to $vbrServer successful."
    } catch {
        Write-Error $Error[0]
        # we can't do anything if this connection fails
        return
    }

    Write-Progress -Activity "Getting all backup jobs from $vbrServer" -Id 1

    # get all backup jobs
    Write-Verbose "Getting all backup jobs."
    $allBackups = Get-VBRBackup | Where-Object {$_.JobType -in $jobTypesScope}
    $allRPs = New-Object -TypeName 'System.Collections.Generic.List[object]'
    $VMJobList = New-Object -TypeName 'System.Collections.Generic.List[string]'
    $countJobs = 0
    $rpId = 0
    $totalRPs = 0
    $totalRPsInBackupWindow = 0


    Write-Progress -Activity $vbrServer -Id 1

    # iterate through backup jobs
    foreach($objBackup in $allBackups) {
        Write-Verbose "Working on job: $($objBackup.JobName)"
        $countJobs++
        Write-Progress -Activity "Iterating through backup jobs" -CurrentOperation "$($objBackup.JobName)" -PercentComplete ($countJobs / $allBackups.Count * 100) -Id 2 -ParentId 1

        $objThisRepo = $objBackup.GetRepository()
        $objRPs = $null
        try {
            # get most recent restore point of current job
            $objRPs = Get-VBRRestorePoint -Backup $objBackup | Sort-Object -Property @{Expression='CreationTime';Descending=$true}, VMName
        } catch {
        }

        $countRPs = 0
        # iterate through all discovered restore points
        foreach($restorePoint in $objRPs) {            
            Write-Progress -Activity "Getting restore points" -PercentComplete ($countRPs / $objRPs.Count * 100) -Id 3 -ParentId 2
            $myBackupJob = $null

            # ignore restore points which are newer than the backup window end time
            if($restorePoint.CreationTime -le $intervalEnd) {

                # only proceed if we do NOT already have a restore point for this VM from this job
                if("$($restorePoint.VmName)-$($objBackup.Name)" -notin $VMJobList){

                    try {
                        $myBackupJob = $objBackup.GetJob()
                    } catch {
                        # ignore error
                    }
                    if($null -eq $myBackupJob ) {
                        $myBlockSize = "[n/a]"
                    } else {
                        $myBlocksize = $jobBlockSizes."$($restorePoint.GetStorage().Blocksize)"
                    }

                    $myBackupType = $restorePoint.algorithm
                    if($myBackupType -eq "Increment") {
                        $myDataRead = $restorePoint.GetStorage().stats.DataSize
                    } else {
                        $myDataRead = $restorePoint.ApproxSize
                    }
                    $myDedup = $restorePoint.GetStorage().stats.DedupRatio
                    $myCompr = $restorePoint.GetStorage().stats.CompressRatio
                    if($myDedup -gt 1) { $myDedup = 100 / $myDedup } else { $myDedup = 1 }
                    if($myCompr -gt 1) { $myCompr = 100 / $myCompr } else { $myCompr = 1 }

                    $extentName = $null
                    if($objThisRepo.TypeDisplay -eq "Scale-out") {
                        $extentName = $restorePoint.FindChainRepositories().Name
                    }

                    # check if rp is within backup window
                    $rpInBackupWindow = $false
                    if(($restorePoint.CreationTime -ge $intervalStart) -and ($restorePoint.CreationTime -le $intervalEnd)) {
                        $rpInBackupWindow = $true
                        $totalRPsInBackupWindow++
                    }

                    $countRPs++
                    $tmpObject = [PSCustomobject]@{
                        RpId = ++$rpID # will be set later!
                        VMName = $restorePoint.VmName
                        BackupJob = $objBackup.Name
                        Repository = $objThisRepo.Name
                        Extent = $extentName
                        RepoType = $restorePoint.FindChainRepositories().Type
                        CreationTime = $restorePoint.CreationTime
                        InBackupWindow = $rpInBackupWindow
                        BackupType = $restorePoint.algorithm
                        ProcessedData = $restorePoint.ApproxSize
                        DataSize = $restorePoint.GetStorage().stats.DataSize
                        DataRead = $myDataRead
                        BackupSize = $restorePoint.GetStorage().stats.BackupSize
                        DedupRatio = $myDedup
                        ComprRatio = $myCompr
                        Reduction = $myDedup * $myCompr
                        Blocksize = $myBlocksize
                        Folder = get_backupfile_path $restorePoint
                        Filename =  $restorePoint.GetStorage().PartialPath.Internal.Elements[0]
                    }

                    $totalRPs++
                    $allRPs.Add($tmpObject) | Out-Null
                    $VMJobList.Add("$($restorePoint.VmName)-$($objBackup.Name)")
                    $tmpObject = $null
                }
            }
        }
    }
    Write-Verbose "Disconnecting from backup server $vbrServer."
    Disconnect-VBRServer -ErrorAction SilentlyContinue
    
    Write-Progress -Activity "Getting restore points" -Id 3 -ParentId 2 -Completed
    Write-Progress -Activity "Iterating through backup jobs" -Id 2 -Completed

    Write-Progress -Activity "Calculating and preparing output..." -Id 2 -ParentId 1
    Write-Verbose "Calculating and preparing output."

    # sort restore points for processing
    $allRPs = $allRPs | Sort-Object -Property VMName, BackupJob, @{Expression='CreationTime';Descending=$true}

    # ...and re-number sorted list
    $rpID = 0
    foreach($rp in $allRPs) {$rp.RpId = ++$rpID }

    # create SLA output object
    $SLACompliance = [math]::Round($totalRPsInBackupWindow/$allRPs.Count *100, 2)
    $SLAObject = [PSCustomobject]@{
        BackupWindowStart = $intervalStart
        BackupWindowEnd = $intervalEnd
        TotalRestorePoints = $allRPs.Count
        RPsInBackupWindow = $totalRPsInBackupWindow
        SLACompliancePercent = $SLACompliance
    }


    # output everything
    # -----------------

    if($allRPs.Count -gt 0) {

        $allRPs | Export-Csv -Path $outfileRP -NoTypeInformation -Delimiter ';'
        Write-Verbose "output file created: $outfileRP"

        $SLAObject | Export-Csv -Path $outfileStatistics -NoTypeInformation -Delimiter ';'
        Write-Verbose "output file created: $outfileStatistics"

        if($displayGrid) {
            # prepare 'human readable' figures for GridViews
            Write-Verbose "Preparing GridViews."
            foreach($rp in $allRPs) {
                $rp.ProcessedData = Format-Bytes $rp.ProcessedData
                $rp.DataSize = Format-Bytes $rp.DataSize
                $rp.DataRead = Format-Bytes $rp.DataRead
                $rp.BackupSize = Format-Bytes $rp.BackupSize
                if($rp.Blocksize -gt 0) { $rp.BlockSize = Format-Bytes $rp.BlockSize }
            }

            # output GridViews
            Write-Verbose "GridView display."
            $allRPs | Out-GridView -Title "List of most recent restore points" -Verbose 
            $SLAObject | Out-GridView -Title "SLA compliance overview" -Verbose 
        }
    }
    Write-Progress -Activity $vbrServer -Id 1 -Completed
    Write-Output ""
    Write-Output "Results from VBR Server ""$vbrServer"""
    Write-Output " Total number of restore points: $totalRPs"
    Write-Output "Restore points in backup window: $totalRPsInBackupWindow"
    Write-Output "                 SLA compliance: $SLACompliance%"

    Write-Verbose "Finished processing backup server $vbrServer."
} 

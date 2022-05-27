
$credFile = "$PSScriptRoot\creds.xml"
$credential = Get-Credential
$credential | Export-CliXml -Path $credFile
"created $credFile"

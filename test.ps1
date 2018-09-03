#test.ps1
# Get the script directory
#$MyInvocation.PSCommandPath
$MyInvocation.MyCommand.Path
$scriptDir = Split-Path -Path $MyInvocation.MyCommand.Path -parent
Write-Host $scriptDir
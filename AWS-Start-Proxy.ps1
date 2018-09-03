<#
    .SYNOPSIS
    Start AWS EC2 instance and create tunnel to use instance as a tunnel
    .DESCRIPTION
    This script launches an AWS EC2 instance that has previously been set up
    to act as a SOCKS5 proxy, will wait for the instance to launch, and then
    create the SSH tunnel that allows it to act as a proxy.
    .PARAMETERS
    -XMLPath
        Mandatory. Path to the XML configuration file that contains AWS information
    -CreateXML
        Optional. Runs function that will prompt for details to create configuration
        XML file. Script will exit after creating XML file.
    .AUTHOR
    PJ Kurylak
 #>

Param(
    [Parameter(Mandatory=$True,Position=1)]
    [string]$XMLPath,

    [Parameter(Mandatory=$False)]
    [string]$CreateXML
)

Function Write-XML {
    <#
    .SYNOPSIS
    Prompts for data neeed for configuration XML file
    .DESCRIPTION
    The AWS-Start-Proxy script requires an XML configuration file. This function
    will interactively prompt for the values of this XML file.
    #>


}

Set-StrictMode -Version 1
# Get the script path
$scriptPath = $MyInvocation.MyCommand.Path
# Build XML file name
$xmlConfigPath = "$($scriptPath.Substring(0, $scriptName.LastIndexOf("."))).xml"
# Get the data from the saved file
[xml]$xmlConfig = Get-Content $xmlConfigPath
# Specify the AWS Credentials to use
# Set this beforehand using a command like 
# 'Set-AWSCredential -AccessKey AKIAIOSFODNN7EXAMPLE -SecretKey wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY -StoreAs MyProfileName'
# See https://docs.aws.amazon.com/powershell/latest/userguide/specifying-your-aws-credentials.html
Set-AWSCredential -ProfileName $xmlConfig.awssession.credentialProfileName
# Set the region
Set-DefaultAWSRegion $xmlConfig.awssession.region
# set the EC2 instance name for the proxy server
$id = $xmlConfig.awssession.ec2Id
# Get an object that represents the EC2 instance
try
$proxyInstance = $(Get-EC2Instance -InstanceId $id)
$state = $proxyInstance.Instances.State.Name
$Timer = New-Object -TypeName System.Diagnostics.Stopwatch
$Timer.Start()

# Get the instance state. Start it if necessary.
While ($state -ne "running" -and $Timer.Elapsed.TotalMinutes -lt 5) {
    switch ( $state )
        {
            "rebooting" { Start-Sleep -s 3 }
            "pending"   { Start-Sleep -s 3 }
            "running"   {
                # No action necessary
            }
            "stopping"  { Start-Sleep -s 3 }
            "stopped"   { Start-EC2Instance -InstanceId $id }
        }
}
# Restart timer to create timeout test for Public IP Address
$Timer.Restart()

# Wait for the public IP address to become available
While ( -Not $proxyInstance.Instances.PublicIPAddress 
    -and $Timer.Elapsed.TotalSeconds -lt 60) {
    Start-Sleep -s 3
}



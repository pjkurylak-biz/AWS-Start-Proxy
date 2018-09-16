<#
    .SYNOPSIS
    Start AWS EC2 instance and create tunnel to use instance as a tunnel
    .DESCRIPTION
    This script launches an AWS EC2 instance that has previously been set up
    to act as a SOCKS5 proxy, will wait for the instance to launch, and then
    create the SSH tunnel that allows it to act as a proxy.
    .PARAMETERS
    -XMLPath
        Optional. Path to the XML configuration file that contains AWS information.
        If not supplied, assumed to be the same path as this script except with
        a ".xml" extension.
    .REQUIREMENTS
        AWSPowerShell module is installed
        Plink (companion program to Putty) has been downloaded
         https://www.chiark.greenend.org.uk/~sgtatham/putty/latest.html
        An EC2 instance has been created to act as the proxy server
        XML Configuration file has been created. See file 'SampleConfig.xml' for required information
    .AUTHOR
    PJ Kurylak
 #>

Param(
    [Parameter(Mandatory=$False,Position=1)]
    [string]$XMLPath
)

Set-StrictMode -Version 1

Write-Host "Starting AWS-Start-Proxy script"
# Read data from XML file
If (-Not $XMLPath) {
# XMLPath is not defined on command line.
# Use the default XML path
    $scriptPath = $MyInvocation.MyCommand.Path
    # Build XML file name - same path as script with ".xml" extension
    $XMLPath = "$($scriptPath.Substring(0, $scriptPath.LastIndexOf("."))).xml"
}
# Get the data from the XML file
Write-Host "Getting settings from `n'$XMLPath'"
[xml]$xmlConfig = Get-Content $XMLPath
# Specify the AWS Credentials to use
# Set this beforehand using a command like 
# 'Set-AWSCredential -AccessKey AKIAIOSFODNN7EXAMPLE -SecretKey wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY -StoreAs MyProfileName'
# See https://docs.aws.amazon.com/powershell/latest/userguide/specifying-your-aws-credentials.html
Set-AWSCredential -ProfileName $xmlConfig.awssession.credentialProfileName
# Set the region
Set-DefaultAWSRegion $xmlConfig.awssession.region
# set the EC2 instance Id for the proxy server
$id = $xmlConfig.awssession.ec2Id
# set the remote port for the proxy
$remotePort = $xmlConfig.awssession.remotePort
# set the local port for the tunnel
$localPort = $xmlConfig.awssession.localPort
# Get the path to plink
$plinkPath = $xmlConfig.awssession.plinkPath
# Get the private key for authentication
$privateKeyPath = $xmlConfig.awssession.privateKeyPath
# Get the hostkey
$hostKey = $xmlConfig.awssession.hostKey

# Get the instance state. Start the instance if it is stopped. 
# Timeout if after 5 minutes it is not 'running'.
$state = $(Get-EC2Instance -InstanceId $id).Instances.State.Name
if (-Not $state ) {
    throw "An Error occurred. Could not get expected EC2 instance."
}
# Create a timer that will allow us to quit after a timeout
$Timer = New-Object -TypeName System.Diagnostics.Stopwatch
$Timer.Start()

# $stateReported contains the last state that we reported.
$stateReported = ""
#Write-Host "Timer (minutes): $($Timer.Elapsed.TotalMinutes)"
While ($stateReported -ne "running" -and $Timer.Elapsed.TotalMinutes -lt 5) {
    switch ( $state )
        {
            #"rebooting" { Start-Sleep -s 3 }
            #"pending"   { Start-Sleep -s 3 }
            "running"   {
                # No action necessary
            }
            #"stopping"  { Start-Sleep -s 3 }
            "stopped"   { 
                Write-Host "Starting proxy server..."
                Start-EC2Instance -InstanceId $id
            }
            default     { Start-Sleep -s 3 }
        }
    If ( $state -ne $stateReported ) {
        Write-Host "Proxy server state : $state"
        $stateReported = $state
    }
    $state = $(Get-EC2Instance -InstanceId $id).Instances.State.Name
}
# See if we timed out
If ($state -ne "running") {
    $Timer.Stop()
    throw "Timed out waiting for instance to start."
}
# Restart timer to create timeout test for Public IP Address
$Timer.Restart()

# Wait for the public IP address to be available
While ( -Not $(Get-EC2Instance -InstanceId $id).Instances.PublicIPAddress `
    -and $Timer.Elapsed.TotalSeconds -lt 60) {
    Start-Sleep -s 3
}
$Timer.Reset >$null

# check that we have a public IP address.
$proxyIP = $(Get-EC2Instance -InstanceId $id).Instances.PublicIPAddress
If (-Not $proxyIP) {
    throw "Could not retrieve proxy public IP address."
}

#Run Plink to set up tunnel
$args = "-ssh" `
    + " -P $remotePort" `
    + " -D $localPort" `
    + " -i `"$privateKeyPath`"" `
    + " -hostkey $hostKey" `
    + " ec2-user@$proxyIP"
# Write-Host $args
#Start-Sleep -s 20
# $connected tells us whether we have ever connected to this instance
$connected = $False
# Timeout trying to connect to instance after 2 minutes.
$Timer.Start()
while ( -not $connected -and $Timer.Elapsed.TotalSeconds -lt 120) {
    # Try to connect. If we get a non-zero exit, then assume that we tried to connect
    # too early, wait and then try again.
    # -PassThru allows us to get the exitcode
    Write-Host "  Running plink..."
    $process = (Start-Process -FilePath $plinkPath -ArgumentList $args -WindowStyle Minimized -Wait -PassThru)
    Write-Host "  Exit code: $($process.ExitCode)"
    if ( $process.ExitCode -eq 0 -or $process.ExitCode -eq -1073741510) {
        # 0 is the preferred exit code
        # in some cases, Plink doesn't close when the ssh session is exited and must be manually closed.
        # In this case it will return '-1073741510' exit code.
        $connected = $True
        Write-Host "  Proxy connection closed."
    } else {
        Write-Host "  Problem connecting to proxy. Proxy is probably not ready. Retry..."
        Start-Sleep -s 5
    }
}
if ( -not $connected ) {
    Write-Error "Could not connect to proxy server before timeout."
    # Don't error out, but continue to stop instance 
}

# When we return from exiting the plink session, close down the proxy server
Write-Host "Stopping proxy server."
Stop-EC2Instance -InstanceId $id >$null
$state = $(Get-EC2Instance -InstanceId $id).Instances.State.Name
Write-Host "Proxy server state is: $state `nEnd of script"

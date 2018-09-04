$args = "-ssh" `
    + " -P 1234" `
    + " -batch" `
    + " -D 8080" `
    + " -i `"C:\Temp\key.ppk`"" `
    + " -hostkey 00:01:02" `
    + " ec2-user@172.17.1.1"
Write-Host $args

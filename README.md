# AWS-Start-Proxy
This script launches an AWS EC2 instance that has previously been set up
to act as a SOCKS5 proxy, will wait for the instance to launch, and then
create the SSH tunnel that allows it to act as a proxy. Once the
tunnel is closed, it will then stop the proxy instance.

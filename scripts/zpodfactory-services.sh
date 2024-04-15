#!/bin/zsh -eu

set -x  # Enable debugging

##
## zPodFactory Services
##

# Directory that will hold each zPod dnsmasq configuration
mkdir -p /zPod/zPodDnsmasqServers

# Create empty file to hold each zPod dnsmasq configuration
touch /zPod/zPodDnsmasqServers/servers.conf

# Install python watchdog for zpod dnsmasq servers service
apt-get install -y python3-pip python3-watchdog

# Enable zdnsmasqservers service
systemctl daemon-reload
systemctl enable zdnsmasqservers.service

# Disable routing daemons, not required.
systemctl disable frr

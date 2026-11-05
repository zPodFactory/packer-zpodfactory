# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

packer-zpodfactory is a Packer-based project that builds a customized Debian Linux VM appliance (zPodFactory) as an OVA. The appliance boots, configures itself from OVF properties or cloud-init, and then deploys the zPodFactory stack on first boot. The zPodFactory application itself is pulled from the `zpodcore` repository at first boot, not built here.

## Build Commands

```bash
# Build the appliance (requires VMware ESXi builder environment)
./build-zpodfactory.sh

# The build script runs:
# packer build --var-file="zpodfactory-builder.json" --var-file="zpodfactory-vars.json" zpodfactory.json
```

**Prerequisites:**
- Copy `zpodfactory-builder.json.sample` to `zpodfactory-builder.json` and configure ESXi builder host settings
- Requires a VMware ESXi environment for Packer to build on

## Architecture

### Packer Configuration

- `zpodfactory.json` - Main Packer template defining the VMware ISO builder, provisioners, and post-processors
- `zpodfactory-vars.json` - Single variables file (Debian version, ISO URL, checksum). The release version is read from the Debian point release in the ISO filename; there is no per-version var file
- `zpodfactory-builder.json` - Builder environment config (ESXi host, credentials, datastore)

### Build Flow

1. **Boot & Install**: Packer boots Debian netinst ISO on ESXi, uses `http/preseed.cfg` for automated installation
2. **Provisioning**: Runs shell scripts from `scripts/` in order:
   - `zpodfactory-update.sh` - apt update and upgrade to latest packages
   - `zpodfactory-apt.sh` - Adds third-party apt repos
   - `zpodfactory-system.sh` - Installs system packages, enables syslog-ng, and related base tooling
   - `zpodfactory-network.sh` - Installs network utilities
   - `zpodfactory-storage.sh` - Installs storage utilities
   - `zpodfactory-settings.sh` - Configures system settings and enables the `zpodfactory-init.sh` boot hook
   - `zpodfactory-shell.sh` - Installs shell environment (zsh, oh-my-posh, tmux)
   - `zpodfactory-vmware.sh` - Installs open-vm-tools and cloud-guest-utils
   - `zpodfactory-services.sh` - Installs and enables appliance services
   - `zpodfactory-cleanup.sh` - Removes unnecessary packages, zeroes disk, cleans logs for smaller OVA export
3. **File Provisioning**: Copies config files from `files/` (`zpodfactory-init.sh` and `zpodfactory-stack.sh` to `/sbin`, the dnsmasq watchdog and its systemd unit, the wireguard compose file, zshrc, tmux.conf, oh-my-posh theme)
4. **Post-processing**: `postprocess-ova-properties/add_ovf_properties.sh` injects OVF properties from `appliance.xml.template` and converts to OVA

### Runtime Initialization

First boot is split in two:

- `files/zpodfactory-init.sh` - Bundled in the OVA. Day-zero OS bootstrap: OVF properties, hostname, network, dnsmasq, NTP, storage, credentials, internet check. Once the internet is reachable, it fetches the current `zpodfactory-stack.sh` from `zpodcore` (`appliance/bootstrap/`), installs it over `/sbin/zpodfactory-stack.sh` only when the sha256 differs, and hands over to it. Any fetch, syntax or copy failure keeps the bundled copy, so a fresh OVA still deploys offline from GitHub.
- `files/zpodfactory-stack.sh` - Stack deployment. `/etc/zpodfactory-stack.locked` pins one stack version per deployment attempt so `--resume` never mixes two versions; `/etc/zpodfactory-stack.version` records which one ran.

### Deployment Methods

1. **OVF Properties**: VM deployed with guestinfo properties (hostname, IP, gateway, DNS, password, SSH key)
2. **Cloud-init**: VM deployed with guestinfo.metadata and guestinfo.userdata (base64+gzip encoded)

## Key Directories

- `scripts/` - Provisioning scripts run during build
- `files/` - Config files copied to the appliance (boot scripts, services, shell config)
- `http/` - Contains preseed.cfg for Debian installer
- `postprocess-ova-properties/` - OVA post-processing for OVF property injection

## Debian Updates

To move to a new Debian point release, set the ISO URL and sha256 in `zpodfactory-vars.json`,
then build and publish the OVA.

## Changelog

- Every change gets a line under `[Unreleased]` in `CHANGELOG.md`: what changed for the person
  deploying the appliance, and why in a clause.
- There are no versions, tags or GitHub releases. When an OVA is published, `## [Unreleased]`
  becomes `## YYYY-MM-DD` (the publish date) with a fresh empty `## [Unreleased]` above it.

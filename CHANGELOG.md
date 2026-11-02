# Changelog

Notable changes to the zPodFactory appliance, newest first. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/). There is a single appliance, rebuilt
regularly, so sections are dated rather than versioned: changes land under `[Unreleased]` as
they are made, and when an OVA is published that section becomes its date (`## 2026-10-10`)
with a fresh `[Unreleased]` above it.

Entries describe what changed for the person deploying the appliance: first-boot behaviour, OVF
properties, services, tools added or removed, disk layout. What the appliance then installs
(zPodFactory itself) is pulled from the `zpodcore` repository at first boot and has its own
history there. The commit history has the reasoning.

## [Unreleased]

### Fixed
- **syslog-ng runs at boot.** Debian 13's `syslog-ng-core` package registers only its sysvinit
  script and never enables the systemd unit, so the appliance came up with the unit
  `disabled` and no `/var/log/syslog`. The system script now enables it explicitly.

## 2026-09-24

### Added
- First boot is split in two. `zpodfactory-init.sh` is bundled in the OVA and does the day-zero
  OS bootstrap: OVF properties, hostname, network, dnsmasq, NTP, storage, credentials, internet
  check. Once the internet is reachable it fetches the current `zpodfactory-stack.sh` from
  `zpodcore` (`appliance/bootstrap/`), installs it over `/sbin/zpodfactory-stack.sh` only when
  the sha256 differs, and hands over to it for the stack deployment. Any fetch, syntax or copy
  failure keeps the bundled copy, so a fresh OVA still deploys offline from GitHub.
- `/etc/zpodfactory-stack.locked` pins one stack version per deployment attempt, so `--resume`
  never mixes two versions; `/etc/zpodfactory-stack.version` records which one ran.

### Changed
- Built on **Debian 13.7** (trixie), from 13.5.
- First-boot log lines for the stack fetch and lock are shorter.

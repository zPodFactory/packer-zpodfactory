#!/bin/zsh

# Parse command line arguments
RESUME_MODE=false
EXTEND_DISK_MODE=false
while [[ $# -gt 0 ]]; do
    case $1 in
        --resume)
            RESUME_MODE=true
            shift
            ;;
        --extend-disk)
            EXTEND_DISK_MODE=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--resume] [--extend-disk]"
            exit 1
            ;;
    esac
done

ZPODFACTORY_OVFENV_FILE="/tmp/ovfenv.xml"
# Path to the configuration file
ZPODFACTORY_CONFIG_FILE="/etc/zpodfactory.config"
# Canonical, fetchable application-provisioning script — see docs/plan_auto-update.md §5.2.
readonly ZPODFACTORY_STACK_URL="https://raw.githubusercontent.com/zPodFactory/zpodcore/main/appliance/bootstrap/zpodfactory-stack.sh"

log() {
    local message="$1"                           # The message to log
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S') # Current timestamp

    echo "$message"
    # Append the timestamp and message to the CONFIG_FILE

    echo "[$timestamp] $message" >>$ZPODFACTORY_CONFIG_FILE
}

# Function to apply OVF settings
appliance_config_ovf_settings() {
    log "Applying OVF settings..."
    # Your OVF settings application commands here
    vmtoolsd --cmd 'info-get guestinfo.ovfEnv' >$ZPODFACTORY_OVFENV_FILE

    OVF_HOSTNAME=$(sed -n 's/.*Property oe:key="guestinfo.hostname" oe:value="\([^"]*\).*/\1/p' $ZPODFACTORY_OVFENV_FILE)
    OVF_DNS=$(sed -n 's/.*Property oe:key="guestinfo.dns" oe:value="\([^"]*\).*/\1/p' $ZPODFACTORY_OVFENV_FILE)
    # Normalize the DNS list so it accepts servers separated by comma and/or space.
    # Commas become spaces, repeated spaces are collapsed, leading/trailing spaces trimmed.
    OVF_DNS=$(echo "$OVF_DNS" | tr ',' ' ' | tr -s ' ' | sed 's/^ *//;s/ *$//')
    OVF_DOMAIN=$(sed -n 's/.*Property oe:key="guestinfo.domain" oe:value="\([^"]*\).*/\1/p' $ZPODFACTORY_OVFENV_FILE)
    OVF_GATEWAY=$(sed -n 's/.*Property oe:key="guestinfo.gateway" oe:value="\([^"]*\).*/\1/p' $ZPODFACTORY_OVFENV_FILE)
    OVF_IPADDRESS=$(sed -n 's/.*Property oe:key="guestinfo.ipaddress" oe:value="\([^"]*\).*/\1/p' $ZPODFACTORY_OVFENV_FILE)
    OVF_NETPREFIX=$(sed -n 's/.*Property oe:key="guestinfo.netprefix" oe:value="\([^"]*\).*/\1/p' $ZPODFACTORY_OVFENV_FILE)
    OVF_PASSWORD=$(sed -n 's/.*Property oe:key="guestinfo.password" oe:value="\([^"]*\).*/\1/p' $ZPODFACTORY_OVFENV_FILE)
    OVF_SSHKEY=$(sed -n 's/.*Property oe:key="guestinfo.sshkey" oe:value="\([^"]*\).*/\1/p' $ZPODFACTORY_OVFENV_FILE)
    OVF_SETUP_WIREGUARD=$(sed -n 's/.*Property oe:key="guestinfo.setup_wireguard" oe:value="\([^"]*\).*/\1/p' $ZPODFACTORY_OVFENV_FILE)
    OVF_GIT_REPOSITORY=$(sed -n 's/.*Property oe:key="guestinfo.git_repository" oe:value="\([^"]*\).*/\1/p' $ZPODFACTORY_OVFENV_FILE)
    OVF_GIT_REPOSITORY=${OVF_GIT_REPOSITORY:-https://github.com/zPodFactory/zpodcore}
    OVF_GIT_BRANCH=$(sed -n 's/.*Property oe:key="guestinfo.git_branch" oe:value="\([^"]*\).*/\1/p' $ZPODFACTORY_OVFENV_FILE)
    OVF_GIT_BRANCH=${OVF_GIT_BRANCH:-main}

    # zpodfactory-stack.sh runs as a separate (exec'd) process — export
    # so it inherits these instead of needing to re-parse OVF env itself.
    export OVF_HOSTNAME OVF_DNS OVF_DOMAIN OVF_GATEWAY OVF_IPADDRESS OVF_NETPREFIX \
        OVF_PASSWORD OVF_SSHKEY OVF_SETUP_WIREGUARD OVF_GIT_REPOSITORY OVF_GIT_BRANCH

    clear
    log "========== OVF Settings =========="
    log "zPodFactory Git Repository: $OVF_GIT_REPOSITORY"
    log "zPodFactory Git Branch: $OVF_GIT_BRANCH"
    log "FQDN: $OVF_HOSTNAME.$OVF_DOMAIN"
    log "IP Address: $OVF_IPADDRESS/$OVF_NETPREFIX"
    log "Gateway: $OVF_GATEWAY"
    log "DNS Server: $OVF_DNS"
    log "Setup Wireguard: $OVF_SETUP_WIREGUARD"
    log "=================================="
}

# Function to configure the host
appliance_config_host() {
    log "Configuring the hostname..."
    # Your host configuration commands here

    # Set the hostname
    hostnamectl set-hostname $OVF_HOSTNAME

    # Set the /etc/hosts file properly
    cat <<EOF >/etc/hosts
127.0.0.1       localhost
$OVF_IPADDRESS  $OVF_HOSTNAME.$OVF_DOMAIN    $OVF_HOSTNAME
EOF
}

# Function to configure the network
appliance_config_network() {
    log "Configuring the network..."
    # Your network configuration commands here

    # Provide code to configure the network with the /etc/network/interfaces file
    cat <<EOF >/etc/network/interfaces
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet static
    address $OVF_IPADDRESS/$OVF_NETPREFIX
    gateway $OVF_GATEWAY
    dns-nameservers $OVF_DNS
EOF

    # restart networking service and check status
    log "Restarting networking..."
    if systemctl restart networking; then
        log "networking successfully restarted."
    else
        log "Failed to restart networking."
        exit 1
    fi
}

# Function to configure dnsmasq
appliance_config_dnsmasq() {
    log "Configuring dnsmasq..."

    # dnsmasq requires one "server=" entry per line, so build a line per DNS server.
    # OVF_DNS is already normalized to a single-space-separated list.
    local dnsmasq_servers=""
    for dns in ${(s: :)OVF_DNS}; do
        dnsmasq_servers+="server=${dns}"$'\n'
    done
    # Strip the trailing newline to avoid an empty line in the config.
    dnsmasq_servers=${dnsmasq_servers%$'\n'}

    # generate /etc/dnsmasq.conf file
    cat <<EOF >/etc/dnsmasq.conf
listen-address=127.0.0.1,$OVF_IPADDRESS
interface=lo,eth0
bind-interfaces
expand-hosts
dns-forward-max=1500
cache-size=10000
no-dhcp-interface=lo,eth0
$dnsmasq_servers
domain=$OVF_DOMAIN
local=/$OVF_DOMAIN/
servers-file=/zPod/zPodDnsmasqServers/servers.conf
EOF

    # restart dnsmasq service and check status
    log "Restarting dnsmasq..."
    if systemctl restart dnsmasq; then
        log "dnsmasq successfully restarted."
    else
        log "Failed to restart dnsmasq."
        exit 1
    fi
}

# Function to configure openntpd
appliance_config_openntpd() {
    log "Configuring openntpd..."

    # Uncomment and set the listen address to the configured IP
    sed -i "s/#listen on \*/listen on $OVF_IPADDRESS/" /etc/openntpd/ntpd.conf

    # Restart openntpd service and check status
    log "Restarting openntpd..."
    if systemctl restart openntpd; then
        log "openntpd successfully restarted."
    else
        log "Failed to restart openntpd."
        exit 1
    fi
}

# Function to configure storage
appliance_config_storage() {
    log "Configuring storage..."

    # Display disk usage before extending partitions
    log "Disk usage before extending partitions:"
    duf -only local

    # Rescan the disk (detect size change)
    echo 1 > /sys/class/block/sda/device/rescan

    # Grow partition 2 on /dev/sda
    if growpart /dev/sda 2; then
        log "Successfully extended partition 2 on /dev/sda."
    else
        log "Failed to extend partition 2 on /dev/sda. Exiting..."
        return 1
    fi

    # Grow partition 5 on /dev/sda
    if growpart /dev/sda 5; then
        log "Successfully extended partition 5 on /dev/sda."
    else
        log "Failed to extend partition 5 on /dev/sda. Exiting..."
        return 1
    fi

    # Resize the physical volume
    if pvresize /dev/sda5; then
        log "Successfully resized physical volume /dev/sda5."
    else
        log "Failed to resize physical volume /dev/sda5. Exiting..."
        return 1
    fi

    # Extend the logical volume to use all available free space
    if lvextend -l +100%FREE /dev/vg/root; then
        log "Successfully extended logical volume /dev/vg/root."
    else
        log "Failed to extend logical volume /dev/vg/root. Exiting..."
        return 1
    fi

    # Resize the filesystem
    if resize2fs /dev/vg/root; then
        log "Successfully resized filesystem on /dev/vg/root."
    else
        log "Failed to resize filesystem on /dev/vg/root. Exiting..."
        return 1
    fi

    # Display disk usage
    log "Disk usage after resizing:"
    duf -only local
}

# Function to configure credentials
appliance_config_credentials() {
    log "Configuring credentials..."

    # Set the password for the root user
    echo "root:$OVF_PASSWORD" | chpasswd

    echo "$OVF_SSHKEY" > ~/.ssh/authorized_keys
}

appliance_check_internet_access() {
    local max_attempts=10
    local timeout=3 # Timeout in seconds
    local target_url="https://www.google.com"

    for ((attempt = 1; attempt <= max_attempts; attempt++)); do
        # Use curl to check internet access. We use the --silent, --head, and --fail flags
        # --silent will hide progress meter or error messages
        # --head will fetch the headers only
        # --fail makes curl treat non-200 HTTP responses as errors
        if curl --silent --head --fail --connect-timeout $timeout $target_url &>/dev/null; then
            log "Internet access confirmed."
            return 0 # Success
        else
            echo "Attempt $attempt of $max_attempts: Checking internet access..."
            log "Internet access check failed. Retrying in $timeout seconds..."
            sleep $timeout
        fi
    done

    log "Failed to confirm internet access after $max_attempts attempts."
    log "Exiting..."
    exit 1 # Failure
}

# Fetches the current zpodfactory-stack.sh from zpodcore and installs it
# over /sbin/zpodfactory-stack.sh only if it differs from what's already
# there. Never touches this file (zpodfactory-init.sh) — only ever the
# separate stack script, which is not currently running. Fail-open: any
# failure leaves /sbin/zpodfactory-stack.sh exactly as it already was
# (OVA-embedded fallback, or a previously fetched copy).
appliance_fetch_stack_script() {
    log "Fetching latest zpodfactory-stack.sh from GitHub zPodFactory/zpodcore ..."

    local candidate="/tmp/zpodfactory-stack.sh.new"
    local current="/sbin/zpodfactory-stack.sh"
    local version_file="/etc/zpodfactory-stack.version"

    if ! curl --fail --silent --show-error --location --max-time 15 \
        --retry 3 --retry-delay 2 \
        -o "$candidate" "$ZPODFACTORY_STACK_URL" 2>>"$ZPODFACTORY_CONFIG_FILE"; then
        log "Fallback to local zpodfactory-stack.sh."
        rm -f "$candidate"
        return 0
    fi

    # Guard against a truncated download or an HTML error page (rate
    # limit, outage) being installed as the real script.
    if ! zsh -n "$candidate" 2>>"$ZPODFACTORY_CONFIG_FILE"; then
        log "Fetched zpodfactory-stack.sh failed syntax check. Fallback to local zpodfactory-stack.sh."
        rm -f "$candidate"
        return 0
    fi

    local current_sha candidate_sha
    current_sha=$(sha256sum "$current" | awk '{print $1}')
    candidate_sha=$(sha256sum "$candidate" | awk '{print $1}')

    if [[ "$current_sha" == "$candidate_sha" ]]; then
        log "Local zpodfactory-stack.sh is up to date (${current_sha:0:12})."
        rm -f "$candidate"
        echo "sha256=$current_sha installed_at=$(date -Iseconds) source=unchanged" >"$version_file"
        return 0
    fi

    log "Newer zpodfactory-stack.sh found (${current_sha:0:12} -> ${candidate_sha:0:12}), installing ..."

    # Keep the pristine OVA-embedded version around once, for diagnostics.
    [[ -f "${current}.orig" ]] || cp "$current" "${current}.orig"

    if ! cp "$candidate" "$current" || ! chmod +x "$current"; then
        log "Failed to install fetched zpodfactory-stack.sh. Fallback to local zpodfactory-stack.sh."
        cp "${current}.orig" "$current" 2>>"$ZPODFACTORY_CONFIG_FILE"
        rm -f "$candidate"
        return 0
    fi

    # Re-verify what actually landed on disk, not just what we intended
    # to write — a failed/partial cp can exit 0 at the shell level while
    # still leaving corrupt content behind.
    if [[ "$(sha256sum "$current" | awk '{print $1}')" != "$candidate_sha" ]]; then
        log "Checksum mismatch after install. Fallback to local zpodfactory-stack.sh."
        cp "${current}.orig" "$current" 2>>"$ZPODFACTORY_CONFIG_FILE"
        rm -f "$candidate"
        return 0
    fi

    rm -f "$candidate"
    echo "sha256=$candidate_sha installed_at=$(date -Iseconds) source=fetched" >"$version_file"
    log "Installed latest zpodfactory-stack.sh (${candidate_sha:0:12})."
}

# Ensures zpodfactory-stack.sh is fetched at most once per deployment
# attempt. The lock is set right before the first hand-off regardless
# of whether that first fetch succeeded or fell back to the embedded
# copy — see docs/plan_auto-update.md §5.5.
appliance_ensure_stack_script() {
    local lock="/etc/zpodfactory-stack.locked"

    if [[ -f "$lock" ]]; then
        log "zpodfactory-stack.sh locked by a prior attempt, reusing installed version."
        return 0
    fi

    appliance_fetch_stack_script
    touch "$lock"
}

# Function to resume zPodFactory setup after internet issues
resume_setup() {
    log "Resuming zPodFactory setup..."

    # We need to reload OVF settings as they are required for zpodfactory setup
    appliance_config_ovf_settings

    # Check internet access before proceeding
    appliance_check_internet_access

    # Fetch (or reuse a locked-in) zpodfactory-stack.sh, then hand off
    appliance_ensure_stack_script

    log "Handing off to zpodfactory-stack.sh..."
    exec /sbin/zpodfactory-stack.sh
}

# Main execution logic
main() {
    if [[ "$EXTEND_DISK_MODE" == "true" ]]; then
        appliance_config_storage
        return
    fi
    if [[ "$RESUME_MODE" == "true" ]]; then
        resume_setup
        return
    fi

    # Check if the configuration file already exists
    if [[ -f "$ZPODFACTORY_CONFIG_FILE" ]]; then
        echo "$ZPODFACTORY_CONFIG_FILE exists. This script has already been executed. Exiting..."
        exit 0
    fi

    # Execute configuration functions
    appliance_config_ovf_settings
    appliance_config_host
    appliance_config_network
    appliance_config_dnsmasq
    appliance_config_openntpd
    appliance_config_storage
    appliance_config_credentials

    # If no internet access is available, the script will exit here
    # as zpodfactory requires internet access to download either
    # the internal dependencies, or even the actual components to be deployed
    appliance_check_internet_access

    # Fetch (or reuse a locked-in) zpodfactory-stack.sh, then hand off
    appliance_ensure_stack_script

    log "Handing off to zpodfactory-stack.sh..."
    exec /sbin/zpodfactory-stack.sh
}

# Invoke the main function
main

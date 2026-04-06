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
    OVF_DOMAIN=$(sed -n 's/.*Property oe:key="guestinfo.domain" oe:value="\([^"]*\).*/\1/p' $ZPODFACTORY_OVFENV_FILE)
    OVF_GATEWAY=$(sed -n 's/.*Property oe:key="guestinfo.gateway" oe:value="\([^"]*\).*/\1/p' $ZPODFACTORY_OVFENV_FILE)
    OVF_IPADDRESS=$(sed -n 's/.*Property oe:key="guestinfo.ipaddress" oe:value="\([^"]*\).*/\1/p' $ZPODFACTORY_OVFENV_FILE)
    OVF_NETPREFIX=$(sed -n 's/.*Property oe:key="guestinfo.netprefix" oe:value="\([^"]*\).*/\1/p' $ZPODFACTORY_OVFENV_FILE)
    OVF_PASSWORD=$(sed -n 's/.*Property oe:key="guestinfo.password" oe:value="\([^"]*\).*/\1/p' $ZPODFACTORY_OVFENV_FILE)
    OVF_SSHKEY=$(sed -n 's/.*Property oe:key="guestinfo.sshkey" oe:value="\([^"]*\).*/\1/p' $ZPODFACTORY_OVFENV_FILE)
    OVF_SETUP_WIREGUARD=$(sed -n 's/.*Property oe:key="guestinfo.setup_wireguard" oe:value="\([^"]*\).*/\1/p' $ZPODFACTORY_OVFENV_FILE)
    OVF_GITHUB_REPOSITORY=$(sed -n 's/.*Property oe:key="guestinfo.github_repository" oe:value="\([^"]*\).*/\1/p' $ZPODFACTORY_OVFENV_FILE)
    OVF_GITHUB_REPOSITORY=${OVF_GITHUB_REPOSITORY:-https://github.com/zPodFactory/zpodcore}
    OVF_GITHUB_BRANCH=$(sed -n 's/.*Property oe:key="guestinfo.github_branch" oe:value="\([^"]*\).*/\1/p' $ZPODFACTORY_OVFENV_FILE)
    OVF_GITHUB_BRANCH=${OVF_GITHUB_BRANCH:-main}

    clear
    log "========== OVF Settings =========="
    log "zPodFactory GitHub Repository: $OVF_GITHUB_REPOSITORY"
    log "zPodFactory GitHub Branch: $OVF_GITHUB_BRANCH"
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

    # generate /etc/dnsmasq.conf file
    cat <<EOF >/etc/dnsmasq.conf
listen-address=127.0.0.1,$OVF_IPADDRESS
interface=lo,eth0
bind-interfaces
expand-hosts
dns-forward-max=1500
cache-size=10000
no-dhcp-interface=lo,eth0
server=$OVF_DNS
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

# Function to configure zPodFactory
appliance_config_zpodfactory() {
    log "Configuring zPodFactory..."
    # Your zPodFactory configuration commands here

    # Update apt repositories
    apt-get -qq update &>> $ZPODFACTORY_CONFIG_FILE

    # Install docker and docker compose plugins for zPodFactory App stack
    apt-get -qq install \
     -o Dpkg::Progress-Fancy="0" \
     -o APT::Color="0" \
     -o Dpkg::Use-Pty="0" \
     -y docker-ce docker-compose-plugin &>> $ZPODFACTORY_CONFIG_FILE

    # Install system packages needed by zPodFactory:
    #  - git: cloning zpodcore
    #  - gcc + libpq-dev: required by `uv sync` on the host when
    #    psycopg2 (used by zpodapi and zpodengine) resolves to a source
    #    distribution. psycopg2's setup.py invokes `cc` directly;
    #    installing gcc creates the /usr/bin/cc alternative link.
    #  - just, bc: justfile runner + column math in the justfile itself
    apt-get -qq install \
     -o Dpkg::Progress-Fancy="0" \
     -o APT::Color="0" \
     -o Dpkg::Use-Pty="0" \
     -y git gcc libpq-dev just bc &>> $ZPODFACTORY_CONFIG_FILE

    # NOTE: uv is installed earlier in main() by appliance_install_uv.
    # uv manages the Python toolchain itself (no pyenv, no system-level
    # python3-dev build chain), so build-essential/libssl-dev/etc. are
    # no longer needed on the appliance.

    # Create root directory for project
    mkdir -p ~/git

    # Clone zPodFactory main repository
    log "Cloning zPodFactory main repository ($OVF_GITHUB_REPOSITORY, branch: $OVF_GITHUB_BRANCH)..."
    git clone -q "$OVF_GITHUB_REPOSITORY" --branch "$OVF_GITHUB_BRANCH" ~/git/zpodcore &>/dev/null

    # Create one uv-managed virtualenv per subproject. Each subproject
    # is released independently and pins its own Python interpreter via
    # `requires-python`; `uv sync --frozen` downloads the matching
    # CPython build automatically (no pyenv compile step).
    for i in zpodsdk zpodapi zpodengine zpodcli; do
        cd ~/git/zpodcore/$i
        log "Running uv sync for $i..."
        uv sync --frozen &>> "$ZPODFACTORY_CONFIG_FILE"
    done

    cd ~/git/zpodcore

    # Set default env to VM settings
    log "Setting up default environment for docker compose stack..."

    cp .env.default .env
    sed -i "s/X.X.X.X/$OVF_IPADDRESS/g" .env

    # Start the zPodFactory services
    log "Building Docker Compose images..."
    docker compose build -q

    log "Starting Docker Compose zPodFactory stack..."

    # Set terminal width to acceptable size for clean logs as this is launched in a script
    export COLUMNS=140
    just -q zpodcore-start-background

    sleep 10

    # Set zcli default entry/token for potential early troubleshooting.
    TOKEN=$(docker compose logs | grep zpodapi | grep 'API Token:' | awk '{ print $5 }' | tr -d '\r')

    just zcli factory add zpodfactory -s http://$OVF_IPADDRESS:8000 -t $TOKEN -a &>> $ZPODFACTORY_CONFIG_FILE


    # Execute first flow to prep prefect
    # This avoids the unique key error "uq_configuration__key" problem when scheduling a lot of deployments to run at the same time
    log "Executing first deployment workflow to prep prefect..."
    just -q zpodengine-cmd python src/zpodengine/flow_init.py

    log "Creating zPodFactory Engine deployments workflows in Prefect..."
    just -q zpodengine-deploy-all


    just zcli setting update zpodfactory_host -v $OVF_IPADDRESS &>> $ZPODFACTORY_CONFIG_FILE
    just zcli setting update zpodfactory_default_domain -v $OVF_DOMAIN &>> $ZPODFACTORY_CONFIG_FILE

    # zpodfactory_ssh_key: use OVF value if set, otherwise generate a key pair for the current user
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
    if [[ -n "$OVF_SSHKEY" ]]; then
        zpodfactory_ssh_key="$OVF_SSHKEY"
    else
        keytype="rsa"
        priv_key="$HOME/.ssh/zpodfactory_$keytype"
        pub_key="$HOME/.ssh/zpodfactory_$keytype.pub"
        if [[ ! -f "$priv_key" ]]; then
            ssh-keygen -t "$keytype" -b 4096 -f "$priv_key" -N "" -q
            log "Generated zPodFactory SSH key at $priv_key"
        fi
        zpodfactory_ssh_key=$(cat "$pub_key")

        # SSH config: use generated zpodfactory key for hosts in the default domain
        {
            [[ -f "$HOME/.ssh/config" ]] && echo ""
            echo "Host *.$OVF_DOMAIN"
            echo "    StrictHostKeyChecking no"
            echo "    IdentityFile $priv_key"
        } >> "$HOME/.ssh/config"
        chmod 600 "$HOME/.ssh/config"
        log "Updated \$HOME/.ssh/config for *.$OVF_DOMAIN"
    fi
    just zcli setting update zpodfactory_ssh_key -v "$zpodfactory_ssh_key" &>> $ZPODFACTORY_CONFIG_FILE

    # Add Default library
    just zcli library create default -u https://github.com/zpodfactory/zpodlibrary -d "Default zPodFactory library" &>> $ZPODFACTORY_CONFIG_FILE

    # Enable component zbox
    just zcli component enable zbox-12.11 &>> $ZPODFACTORY_CONFIG_FILE

    # Store API token for zpodweb and zpod-vcf-deployer (from .zclirc written by zcli factory add)
    local zclirc="$HOME/.config/zcli/.zclirc"
    if [[ -f "$zclirc" ]]; then
        ZPOD_API_TOKEN=$(grep 'zpod_api_token' "$zclirc" 2>/dev/null | cut -d "=" -f 2 | tr -d '\r' | xargs)
    fi

    log "zPodFactory setup complete."
}

appliance_config_vcf_offline_depot() {
    log "Preparing VCF offline depot..."

    local repo_dir=~/git/doc-vcf-offlinedepot

    if [[ ! -d "$repo_dir/.git" ]]; then
        log "Cloning doc-vcf-offlinedepot repository..."
        git clone -q https://github.com/tsugliani/doc-vcf-offlinedepot "$repo_dir" &>> "$ZPODFACTORY_CONFIG_FILE" || {
            log "Failed to clone doc-vcf-offlinedepot repository."
            return 1
        }
    else
        log "doc-vcf-offlinedepot repository already present. Skipping clone."
    fi


    # Ensure depot root directory exists (used later by UMDS / VCF tooling)
    mkdir -p /depot

    # Ensure the service-network exists for external compose stacks in the repo
    if ! docker network ls --format '{{.Name}}' | grep -q '^service-network$'; then
        log "Creating Docker network service-network..."
        docker network create service-network &>> "$ZPODFACTORY_CONFIG_FILE" || log "Failed to create Docker network service-network."
    else
        log "Docker network service-network already exists."
    fi

    log "VCF offline depot repository ready."
}

appliance_config_zpodweb_ui() {
    log "Configuring zPodFactory Web UI (zpodweb)..."

    local repo_dir=~/git/zpodweb

    if [[ ! -d "$repo_dir/.git" ]]; then
        log "Cloning zpodweb repository..."
        git clone -q https://github.com/zPodFactory/zpodweb "$repo_dir" &>> "$ZPODFACTORY_CONFIG_FILE" || {
            log "Failed to clone zpodweb repository."
            return 1
        }
    else
        log "zpodweb repository already present. Skipping clone."
    fi

    cd "$repo_dir" || {
        log "Failed to enter zpodweb directory."
        return 1
    }

    if [[ ! -f ".env" && -f ".env.example" ]]; then
        log "Creating .env from .env.example for zpodweb..."
        cp .env.example .env
    elif [[ ! -f ".env" ]]; then
        log "Creating empty .env for zpodweb (no .env.example found)..."
        touch .env
    fi

    # Configure API URL
    if grep -q '^ZPODWEB_DEFAULT_ZPODFACTORY_API_URL=' .env; then
        sed -i "s|^ZPODWEB_DEFAULT_ZPODFACTORY_API_URL=.*$|ZPODWEB_DEFAULT_ZPODFACTORY_API_URL=http://$OVF_IPADDRESS:8000|" .env
    fi

    # Set API token (from ZPOD_API_TOKEN set by appliance_config_zpodfactory)
    if [[ -n "$ZPOD_API_TOKEN" ]]; then
        if grep -q '^ZPODWEB_DEFAULT_ZPODFACTORY_API_TOKEN=' .env; then
            sed -i "s|^ZPODWEB_DEFAULT_ZPODFACTORY_API_TOKEN=.*$|ZPODWEB_DEFAULT_ZPODFACTORY_API_TOKEN=$ZPOD_API_TOKEN|" .env
        else
            echo "ZPODWEB_DEFAULT_ZPODFACTORY_API_TOKEN=$ZPOD_API_TOKEN" >> .env
        fi
        log "Set ZPODWEB_DEFAULT_ZPODFACTORY_API_TOKEN from ZPOD_API_TOKEN."
    fi

    # Start zpodweb Docker Compose stack
    if [[ -f "docker-compose.yml" ]]; then
        log "Starting zpodweb Docker Compose stack..."
        docker compose up -d &>> "$ZPODFACTORY_CONFIG_FILE" || log "Failed to start zpodweb Docker Compose stack."
    else
        log "No docker-compose.yml found for zpodweb, skipping stack startup."
    fi
}

appliance_config_zpod_vcf_deployer() {
    log "Configuring zPod VCF Deployer..."

    local repo_dir=~/git/zpod-vcf-deployer

    if [[ ! -d "$repo_dir/.git" ]]; then
        log "Cloning zpod-vcf-deployer repository..."
        git clone -q https://github.com/zPodFactory/zpod-vcf-deployer "$repo_dir" &>> "$ZPODFACTORY_CONFIG_FILE" || {
            log "Failed to clone zpod-vcf-deployer repository."
            return 1
        }
    else
        log "zpod-vcf-deployer repository already present. Skipping clone."
    fi

    cd "$repo_dir" || {
        log "Failed to enter zpod-vcf-deployer directory."
        return 1
    }

    if [[ ! -f ".env" && -f "env_example.txt" ]]; then
        log "Creating .env from env_example.txt for zpod-vcf-deployer..."
        cp env_example.txt .env
    fi

    # Configure base URL to local zPodFactory
    if grep -q '^ZPODFACTORY_BASE_URL=' .env; then
        sed -i "s|^ZPODFACTORY_BASE_URL=.*$|ZPODFACTORY_BASE_URL=http://$OVF_IPADDRESS:8000|" .env
    fi

    # Configure offline depot hostname (FQDN)
    local depot_fqdn="$OVF_HOSTNAME.$OVF_DOMAIN"
    if grep -q '^VCF_OFFLINE_DEPOT_HOSTNAME=' .env; then
        sed -i "s|^VCF_OFFLINE_DEPOT_HOSTNAME=.*$|VCF_OFFLINE_DEPOT_HOSTNAME=$depot_fqdn|" .env
    fi

    # Configure offline depot username (static)
    if grep -q '^VCF_OFFLINE_DEPOT_USERNAME=' .env; then
        sed -i "s|^VCF_OFFLINE_DEPOT_USERNAME=.*$|VCF_OFFLINE_DEPOT_USERNAME=secure|" .env
    fi

    # Set API token (from ZPOD_API_TOKEN set by appliance_config_zpodfactory)
    if [[ -n "$ZPOD_API_TOKEN" ]]; then
        if grep -q '^ZPODFACTORY_ACCESS_TOKEN=' .env; then
            sed -i "s|^ZPODFACTORY_ACCESS_TOKEN=.*$|ZPODFACTORY_ACCESS_TOKEN=$ZPOD_API_TOKEN|" .env
        fi
        log "Set ZPODFACTORY_ACCESS_TOKEN from ZPOD_API_TOKEN."
    fi

    # Start deployer stack if docker-compose is present
    if [[ -f "docker-compose.yml" ]]; then
        log "Starting zpod-vcf-deployer Docker Compose stack..."
        docker compose up -d &>> "$ZPODFACTORY_CONFIG_FILE" || log "Failed to start zpod-vcf-deployer Docker Compose stack."
    else
        log "No docker-compose.yml found for zpod-vcf-deployer, skipping stack startup."
    fi
}

appliance_install_uv() {
    # uv is the Python package & toolchain manager used by every zpodcore
    # subproject (replaces the old pyenv + poetry combo). We install it
    # here so it is available early in the boot sequence for every
    # subsequent function that needs Python tooling (zpodcore itself,
    # zpod-vcf-deployer, etc.). Requires internet access — call after
    # appliance_check_internet_access.
    #
    # IMPORTANT: this function is called at firstboot from a systemd
    # unit with a sparse environment. $HOME may be unset, and the
    # interactive shell init files (~/.zshrc, ~/.bashrc) that the uv
    # installer patches are NOT sourced by this non-interactive script.
    # The function must therefore guarantee that `uv` is on PATH and
    # callable in the current process before returning.

    local uv_bin_dir="$HOME/.local/bin"
    local uv_bin="$uv_bin_dir/uv"

    if command -v uv &>/dev/null; then
        log "uv already installed ($(uv --version 2>/dev/null)). Skipping install."
    else
        log "Installing uv..."
        # Pin the install location explicitly — the installer respects
        # UV_INSTALL_DIR and XDG_BIN_HOME. Being explicit means we know
        # exactly where the binary lands regardless of the invoking
        # user's XDG env (or lack thereof).
        UV_INSTALL_DIR="$uv_bin_dir" \
            curl -LsSf https://astral.sh/uv/install.sh | sh &>> "$ZPODFACTORY_CONFIG_FILE" || {
            log "Failed to install uv."
            exit 1
        }
    fi

    # Verify the binary actually landed on disk before we touch PATH —
    # this catches a silent installer failure that `command -v` wouldn't
    # catch until after we rehash.
    if [[ ! -x "$uv_bin" ]]; then
        log "uv binary not found at $uv_bin after install. Aborting."
        exit 1
    fi

    # Prepend the install dir to PATH for the current process so every
    # subsequent function in this script sees `uv`.
    case ":$PATH:" in
        *":$uv_bin_dir:"*) ;;
        *) export PATH="$uv_bin_dir:$PATH" ;;
    esac

    # Flush zsh's command hash table — without this, a later bare `uv`
    # call can still resolve to a stale "command not found" cache entry
    # even though PATH is now correct.
    rehash 2>/dev/null || hash -r 2>/dev/null || true

    # Also persist PATH into ~/.zshrc for future interactive shells on
    # the appliance (post-firstboot operator logins). The uv installer
    # usually handles this itself, but we make it explicit and
    # idempotent so it survives re-runs and older installer scripts.
    if [[ -f "$HOME/.zshrc" ]] && ! grep -q 'HOME/.local/bin' "$HOME/.zshrc"; then
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.zshrc"
    fi

    # Final sanity check — uv must be callable via PATH lookup, not just
    # via absolute path, because later code uses bare `uv` invocations.
    if ! command -v uv &>/dev/null; then
        log "uv is not on PATH after install (PATH=$PATH). Aborting."
        exit 1
    fi

    log "uv installed and on PATH: $(uv --version) at $(command -v uv)"
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

appliance_config_wireguard() {
    if [[ "$OVF_SETUP_WIREGUARD" == "False" ]]; then
        log "Wireguard setup disabled..."
        return 1
    fi

    log "Setting up Wireguard..."

    mkdir -p ~/wireguard
    cp ~/docker-compose.wireguard.yml ~/wireguard/docker-compose.yml

    sed -i "s/HOSTNAME/$OVF_HOSTNAME/g" ~/wireguard/docker-compose.yml
    sed -i "s/IPADDRESS/$OVF_IPADDRESS/g" ~/wireguard/docker-compose.yml
    sed -i "s/DOMAIN/$OVF_DOMAIN/g" ~/wireguard/docker-compose.yml

    # log "Launching Wireguard Docker Compose Stack..."
    # cd ~/wireguard
    # docker compose up -d

    rm -f ~/docker-compose.wireguard.yml
}

# Function to resume zPodFactory setup after internet issues
resume_setup() {
    log "Resuming zPodFactory setup..."

    # We need to reload OVF settings as they are required for zpodfactory setup
    appliance_config_ovf_settings

    # Check internet access before proceeding
    appliance_check_internet_access

    # Ensure uv is available (required by zpodcore + zpod-vcf-deployer)
    appliance_install_uv

    # Continue with zpodfactory setup
    appliance_config_zpodfactory
    appliance_config_zpodweb_ui
    appliance_config_vcf_offline_depot
    appliance_config_zpod_vcf_deployer
    appliance_config_wireguard

    log "Resume setup complete."
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

    # Install uv up front — it is the Python toolchain for every
    # downstream step (zpodcore subprojects, zpod-vcf-deployer, ...).
    appliance_install_uv

    appliance_config_zpodfactory
    appliance_config_zpodweb_ui
    appliance_config_vcf_offline_depot
    appliance_config_zpod_vcf_deployer
    appliance_config_wireguard

    log "zPodFactory setup complete"
}

# Invoke the main function
main

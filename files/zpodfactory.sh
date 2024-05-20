#!/bin/zsh

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
    OVF_ZPODFACTORY_VERSION=$(sed -n 's/.*Property oe:key="guestinfo.zpodfactory_version" oe:value="\([^"]*\).*/\1/p' $ZPODFACTORY_OVFENV_FILE)

    clear
    log "========== OVF Settings =========="
    log "zPodFactory Version: $OVF_ZPODFACTORY_VERSION"
    log "FQDN: $OVF_HOSTNAME.$OVF_DOMAIN"
    log "DNS: $OVF_DNS"
    log "Gateway: $OVF_GATEWAY"
    log "IP Address: $OVF_IPADDRESS/$OVF_NETPREFIX"
    log "Setup Wireguard: $OVF_SETUP_WIREGUARD"
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

# Function to configure storage
appliance_config_storage() {
    log "Configuring storage..."
    # Your storage configuration commands here

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

    # Install docker and docker compose plugins for zPodFactory App stack
    apt-get -qq install \
     -o Dpkg::Progress-Fancy="0" \
     -o APT::Color="0" \
     -o Dpkg::Use-Pty="0" \
     -y docker-ce docker-compose-plugin &>> $ZPODFACTORY_CONFIG_FILE

    # Install build packages to be able to compile python through pyenv
    apt-get -qq install \
     -o Dpkg::Progress-Fancy="0" \
     -o APT::Color="0" \
     -o Dpkg::Use-Pty="0" \
     -y build-essential libssl-dev zlib1g-dev libbz2-dev \
        libreadline-dev libsqlite3-dev llvm libncurses5-dev libncursesw5-dev \
        libffi-dev liblzma-dev python3-openssl git libpq-dev &>> $ZPODFACTORY_CONFIG_FILE

    # Install some misc tools for zPodFactory
    apt-get -qq install \
     -o Dpkg::Progress-Fancy="0" \
     -o APT::Color="0" \
     -o Dpkg::Use-Pty="0" \
     -y just bc &>> $ZPODFACTORY_CONFIG_FILE


    # Install pyenv
    log "Cloning pyenv repository..."
    git clone -q https://github.com/pyenv/pyenv.git ~/.pyenv

    # Setup pyenv to shell environment
    echo 'export PYENV_ROOT="$HOME/.pyenv"' >> ~/.zshrc
    echo 'command -v pyenv >/dev/null || export PATH="$PYENV_ROOT/bin:$PATH"' >> ~/.zshrc
    echo 'eval "$(pyenv init -)"' >> ~/.zshrc

    source ~/.zshrc

    log "Installing/Compiling Python 3.12.1..."
    # Install/Compile python version required for the project
    pyenv install 3.12.1

    # Create root directory for project
    mkdir -p ~/git

    # Clone zPodFactory main repository
    log "Cloning zPodFactory main repository..."
    if [[ "$version" == "latest" ]]; then
        git clone -q https://github.com/zpodfactory/zpodcore ~/git/zpodcore &>/dev/null
    else
        git clone -q https://github.com/zpodfactory/zpodcore --branch v$OVF_ZPODFACTORY_VERSION ~/git/zpodcore &>/dev/null
    fi

    for i in zpodapi zpodengine zpodcli; do
        cd ~/git/zpodcore/$i
        log "Setting up Python and poetry for $i..."
        pyenv local 3.12.1
        pyenv exec pip install --upgrade pip &>> "$ZPODFACTORY_CONFIG_FILE"
        pyenv exec pip install poetry &>> "$ZPODFACTORY_CONFIG_FILE"
        poetry config virtualenvs.in-project true
        poetry -q install
    done

    # Setup pyenv for zPodCore/just zcli locally
    cd ~/git/zpodcore
    log "Setting up Python and poetry for zpodcore..."
    pyenv local 3.12.1
    pyenv exec pip install --upgrade pip &>> "$ZPODFACTORY_CONFIG_FILE"
    pyenv exec pip install poetry &>> "$ZPODFACTORY_CONFIG_FILE"


    # Set default env to VM settings
    log "Setting up default environment for docker compose stack..."

    cp .env.default .env
    sed -i "s/X.X.X.X/$OVF_IPADDRESS/g" .env

    # Start the zPodFactory services
    log "Building Docker Compose images..."
    docker compose build -q

    log "Starting Docker Compose zPodFactory stack..."
    just -q zpodcore-start-background

    sleep 10

    # Set zcli default entry/token for potential early troubleshooting.
    TOKEN=$(docker compose logs | grep zpodapi | grep 'API Token:' | awk '{ print $5 }')

    just zcli factory add zpodfactory -s http://$OVF_IPADDRESS:8000 -t $TOKEN -a &>> $ZPODFACTORY_CONFIG_FILE


    # Execute first flow to prep prefect
    # This avoids the unique key error "uq_configuration__key" problem when scheduling a lot of deployments to run at the same time
    log "Executing first deployment workflow to prep prefect..."
    just -q zpodengine-cmd python src/zpodengine/flow_init.py

    log "Creating zPodFactory Engine deployments workflows in Prefect..."
    just -q zpodengine-deploy-all



    just zcli setting update zpodfactory_host -v $OVF_IPADDRESS &>> $ZPODFACTORY_CONFIG_FILE
    just zcli setting update zpodfactory_default_domain -v $OVF_DOMAIN &>> $ZPODFACTORY_CONFIG_FILE
    just zcli setting update zpodfactory_ssh_key -v $OVF_SSHKEY &>> $ZPODFACTORY_CONFIG_FILE

    # Add Default library
    just zcli library create default -u https://github.com/zpodfactory/zpodlibrary -d "Default zPodFactory library" &>> $ZPODFACTORY_CONFIG_FILE

    # Enable component zbox
    just zcli component enable zbox-12.4 &>> $ZPODFACTORY_CONFIG_FILE

    # Enable component esxi
    just zcli component enable esxi-8.0u2b &>> $ZPODFACTORY_CONFIG_FILE

    log "zPodFactory setup complete."
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


# Main execution logic
main() {
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
    appliance_config_storage
    appliance_config_credentials

    # If no internet access is available, the script will exit here
    # as zpodfactory requires internet access to download either
    # the internal dependencies, or even the actual components to be deployed
    appliance_check_internet_access

    appliance_config_zpodfactory
    appliance_config_wireguard

    # Mark the setup as complete by creating the configuration file
    touch "$ZPODFACTORY_CONFIG_FILE"
    echo "Setup complete. Configuration file created at $ZPODFACTORY_CONFIG_FILE."
}

# Invoke the main function
main

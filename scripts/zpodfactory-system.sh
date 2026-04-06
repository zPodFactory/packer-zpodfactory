#!/bin/bash -eux

##
## Debian system
## Install system utilities
##

echo '> Installing System Utilities...'

apt-get install -y \
  jq \
  bat \
  duf \
  eza \
  fzf \
  git \
  lsd \
  man \
  vim \
  btop \
  file \
  htop \
  lnav \
  make \
  ccze \
  tree \
  tmux \
  bzip2 \
  dstat \
  unzip \
  direnv \
  httpie \
  colordiff \
  colortail \
  syslog-ng


#
# Install fx (JSON tool)
# https://github.com/antonmedv/fx
#
curl https://fx.wtf/install.sh | sh


#
# Install chezmoi (https://chezmoi.io/)
# https://github.com/twpayne/chezmoi
#
curl -s https://api.github.com/repos/twpayne/chezmoi/releases/latest \
| grep browser_download_url \
| grep linux_amd64.deb \
| cut -d '"' -f 4 \
| xargs curl -LO \
&& dpkg -i chezmoi_*_linux_amd64.deb && rm chezmoi_*_linux_amd64.deb



echo '> Done'

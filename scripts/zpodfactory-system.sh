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
  exa \
  fzf \
  git \
  lsd \
  man \
  vim \
  btop \
  htop \
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
  syslog-ng \
  cloud-guest-utils

echo '> Done'

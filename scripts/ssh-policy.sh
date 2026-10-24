#!/bin/bash
# Routing settings may be inherited; forwarding, trust and multiplexing may not.
telynd_ssh_policy() {
  local trust=$1 identity=$2
  case "$trust" in ask|yes) ;; *) return 2;; esac
  # SSH parses -o using configuration syntax, in addition to shell argv rules.
  local quoted_identity=${identity//\\/\\\\}
  quoted_identity=${quoted_identity//\"/\\\"}
  telynd_ssh_options=(
    -o "StrictHostKeyChecking=$trust"
    -o ForwardAgent=no -o ForwardX11=no -o ForwardX11Trusted=no
    -o ClearAllForwardings=yes -o PermitLocalCommand=no
    -o ControlMaster=no -o ControlPath=none -o ControlPersist=no
    -o ForkAfterAuthentication=no
    -o ConnectTimeout=10 -o ServerAliveInterval=5 -o ServerAliveCountMax=2
    -o IgnoreUnknown=UseKeychain -o UseKeychain=yes -o AddKeysToAgent=yes
    -o IdentitiesOnly=yes -o "IdentityFile=\"$quoted_identity\""
  )
}

#!/usr/bin/env bash
# Shared VM/SSH plumbing for the host-side scripts. Source it; it only sets variables.
#
# The password comes from Doppler (`conduit/dev` -> MACOS_SSH_PASSWORD), so remote
# commands run under `doppler run --project conduit --config dev -- sh -lc '...'`
# with `export SSHPASS="$MACOS_SSH_PASSWORD"` before using $VM_SSH / $VM_SCP.

: "${VM_SSH_USER:=w3}"
: "${VM_SSH_HOST:=localhost}"
: "${VM_SSH_PORT:=2222}"

: "${VM_REPO:=/Users/${VM_SSH_USER}/opencode-remote}"
: "${VM_REPO_BASE:=/Users/base/opencode-remote}"
: "${VM_SCRIPT_DIR:=/Users/${VM_SSH_USER}}"
: "${VM_XCODEGEN:=/Users/${VM_SSH_USER}/tools/xcodegen/xcodegen/bin/xcodegen}"

: "${SIMULATOR_UDID:=6424C025-2006-4270-8C5B-619E4D74085F}"
: "${BUNDLE_ID:=dev.sebstaq.opencode.OpenCodeRemote}"
: "${XCODE_DERIVED:=/Users/${VM_SSH_USER}/Library/Developer/Xcode/DerivedData/OpenCodeRemote-fkgcsynjxhpjokewsyypoxdmpmqe}"

VM_SSH="sshpass -e ssh -o StrictHostKeyChecking=no -o PubkeyAuthentication=no -p ${VM_SSH_PORT} ${VM_SSH_USER}@${VM_SSH_HOST}"
VM_SCP="sshpass -e scp -q -o StrictHostKeyChecking=no -o PubkeyAuthentication=no -P ${VM_SSH_PORT}"
VM_RSYNC_SSH="sshpass -e ssh -o StrictHostKeyChecking=no -p ${VM_SSH_PORT}"

# Runs a remote command with the keychain/SSH password available. Call inside
# `doppler run --project conduit --config dev --`.
vm_ssh() {
  (
    export SSHPASS="$MACOS_SSH_PASSWORD"
    $VM_SSH "$@"
  )
}

vm_scp() {
  (
    export SSHPASS="$MACOS_SSH_PASSWORD"
    $VM_SCP "$@"
  )
}

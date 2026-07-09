#!/usr/bin/env bash
set -euo pipefail

EKT_ENABLED="${ENABLE_EKT_SERVER:-false}"

PLUGIN_PATH="/opt/belledonne-communications/flexisip-conference/lib/liblinphone/plugins/liblinphone_ektserver.so"
CONFIG_PATH="/etc/opt/belledonne-communications/flexisip-conference/flexisip-conference.conf"

# --- Plugin presence check (always) ----------------------------------------
if [[ -f "$PLUGIN_PATH" ]]; then
  echo "[entrypoint] EKT plugin present: $PLUGIN_PATH"
else
  echo "[entrypoint] WARNING: EKT plugin not found at $PLUGIN_PATH" >&2
  echo "[entrypoint]          (image was built without EKT, or install prefix differs)" >&2
  echo "[entrypoint]          conferences will NOT be end-to-end encryptable" >&2
fi

# --- E2EE opt-in handling ---------------------------------------------------
if [[ "${EKT_ENABLED,,}" == "true" ]]; then
  if [[ ! -f "$PLUGIN_PATH" ]]; then
    echo "[entrypoint] ERROR: ENABLE_EKT_SERVER=true but the EKT plugin is not installed." >&2
    exit 1
  fi

  if [[ ! -f "$CONFIG_PATH" ]]; then
    echo "[entrypoint] ERROR: ENABLE_EKT_SERVER=true but no config file at $CONFIG_PATH" >&2
    echo "[entrypoint]        Mount your flexisip-conference.conf to that path and retry." >&2
    exit 1
  fi

  if ! grep -qE '^\s*audio-engine-mode\s*=' "$CONFIG_PATH"; then
    echo "[entrypoint] E2EE mode active: appending SFU + ZRTP block to $CONFIG_PATH"
    cat >> "$CONFIG_PATH" <<'EOF'

# --- E2EE block: appended by entrypoint when ENABLE_EKT_SERVER=true ---
[conference-server]
audio-engine-mode=sfu
video-engine-mode=sfu
encryption=zrtp
# ----------------------------------------------------------------------
EOF
  else
    echo "[entrypoint] E2EE mode active: $CONFIG_PATH already declares engine-mode keys; leaving as-is"
    echo "[entrypoint]          (verify audio-engine-mode=sfu, video-engine-mode=sfu, encryption=zrtp)"
  fi

  echo "[entrypoint] E2EE mode ACTIVE"
else
  echo "[entrypoint] E2EE mode DISABLED (ENABLE_EKT_SERVER=${EKT_ENABLED}); running with default mixer engine mode"
fi

exec "$@"

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

# --- E2EE configuration (NO runtime rewriting) -----------------------------
# E2EE (SFU engine + ZRTP) is configured directly in the mounted
# flexisip-conference.conf ([conference-server] audio-engine-mode=sfu,
# video-engine-mode=sfu, encryption=zrtp). This entrypoint does NOT rewrite the
# config file. ENABLE_EKT_SERVER in .env is retained only as an intent signal.
if [[ "${EKT_ENABLED,,}" == "true" ]]; then
  echo "[entrypoint] E2EE is configured via flexisip-conference.conf (SFU + ZRTP). ENABLE_EKT_SERVER is an intent signal only."
else
  echo "[entrypoint] NOTE: ENABLE_EKT_SERVER is not 'true'; E2EE still depends on flexisip-conference.conf (SFU + ZRTP)."
fi

exec "$@"

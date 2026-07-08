#!/usr/bin/env bash
set -euo pipefail

if [[ "${ENABLE_EKT_SERVER:-false}" == "true" ]]; then
  echo "[entrypoint] WARNING: ENABLE_EKT_SERVER=true is set, but it is ignored on the proxy. The conference service controls E2EE." >&2
fi

exec "$@"

#!/usr/bin/env sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
DEFAULT_ENV_FILE="$SCRIPT_DIR/connection-state.example.env"
ENV_FILE="$DEFAULT_ENV_FILE"

print_usage() {
  cat <<'EOF'
Usage:
  run-bootstrap-check.sh [--env-file <path>]

Options:
  --env-file <path>  Use a connection-state env file from the direct iOS DJI SDK probe.
  -h, --help         Show this help.
EOF
}

log() {
  level="$1"
  shift
  printf "%s [%s] %s\n" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" "$level" "$*"
}

contains_word() {
  haystack="$1"
  needle="$2"

  for value in $haystack; do
    if [ "$value" = "$needle" ]; then
      return 0
    fi
  done

  return 1
}

require_var() {
  name="$1"
  eval "value=\${$name-}"
  if [ -z "$value" ]; then
    log "ERROR" "Missing required variable: $name"
    return 1
  fi
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --env-file)
      if [ "$#" -lt 2 ]; then
        log "ERROR" "Missing value for --env-file"
        exit 64
      fi
      ENV_FILE="$2"
      shift 2
      ;;
    -h|--help)
      print_usage
      exit 0
      ;;
    *)
      log "ERROR" "Unknown argument: $1"
      print_usage
      exit 64
      ;;
  esac
done

if [ ! -f "$ENV_FILE" ]; then
  log "ERROR" "Connection-state file not found: $ENV_FILE"
  exit 66
fi

log "INFO" "Loading DJI bootstrap state from: $ENV_FILE"

# shellcheck disable=SC1090
. "$ENV_FILE"

require_var "DJI_SDK_MANAGER_STATE"
require_var "DJI_REGISTRATION_STATE"
require_var "DJI_BASE_PRODUCT_CONNECTED"
require_var "DJI_CONNECTED_PRODUCT_CLASS"
require_var "DJI_CONNECTED_PRODUCT_MODEL"
DJI_SUPPORTED_PRODUCT_CLASSES="${DJI_SUPPORTED_PRODUCT_CLASSES:-AIRCRAFT}"
require_var "DJI_SUPPORTED_PRODUCT_CLASSES"

log "INFO" "Connection state:"
log "INFO" "  sdk_manager_state=${DJI_SDK_MANAGER_STATE}"
log "INFO" "  registration_state=${DJI_REGISTRATION_STATE}"
log "INFO" "  base_product_connected=${DJI_BASE_PRODUCT_CONNECTED}"
log "INFO" "  connected_product_class=${DJI_CONNECTED_PRODUCT_CLASS}"
log "INFO" "  connected_product_model=${DJI_CONNECTED_PRODUCT_MODEL}"
log "INFO" "  supported_product_classes=${DJI_SUPPORTED_PRODUCT_CLASSES}"

failed=0

if [ "$DJI_SDK_MANAGER_STATE" != "ready" ]; then
  log "ERROR" "SDK manager is not ready (expected: ready)"
  failed=1
fi

if [ "$DJI_REGISTRATION_STATE" != "success" ]; then
  log "ERROR" "DJI registration did not succeed (expected: success)"
  failed=1
fi

if [ "$DJI_BASE_PRODUCT_CONNECTED" != "true" ]; then
  log "ERROR" "Base product is not connected (expected: true)"
  failed=1
fi

if ! contains_word "$DJI_SUPPORTED_PRODUCT_CLASSES" "$DJI_CONNECTED_PRODUCT_CLASS"; then
  log "ERROR" "Connected product class '$DJI_CONNECTED_PRODUCT_CLASS' is not supported"
  failed=1
fi

if [ "$DJI_CONNECTED_PRODUCT_CLASS" = "AIRCRAFT" ] && [ -z "$DJI_CONNECTED_PRODUCT_MODEL" ]; then
  log "ERROR" "Aircraft class requires a non-empty model value"
  failed=1
fi

if [ "$failed" -ne 0 ]; then
  log "ERROR" "DJI bootstrap verification failed. Supported chain was not confirmed."
  exit 1
fi

log "INFO" "Supported DJI chain detected: SDKManager -> BaseProduct -> ${DJI_CONNECTED_PRODUCT_CLASS} (${DJI_CONNECTED_PRODUCT_MODEL})"
log "INFO" "Direction confirmed: direct iOS DJI Mobile SDK (Bridge App mode not required)"
log "INFO" "DJI bootstrap verification passed."

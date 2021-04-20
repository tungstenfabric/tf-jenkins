#!/bin/bash
set -e

DEVPI_USER="${DEVPI_USER:-www-data}"

mkdir -p "$DEVPI_SERVERDIR"
chown -R "$DEVPI_USER" "$DEVPI_SERVERDIR"

#    "--request-timeout=120" \
exec gosu "$DEVPI_USER" devpi-server \
    --host=0.0.0.0 \
    "--replica-max-retries=10" \
    "--mirror-cache-expiry=604800" \
    "--serverdir=$DEVPI_SERVERDIR" \
    "--secretfile=$DEVPI_SERVERDIR/.secret" \
    "--restrict-modify=${DEVPI_RESTRICT_MODIFY:-root}" \
    "--role=master" \
    "$@"

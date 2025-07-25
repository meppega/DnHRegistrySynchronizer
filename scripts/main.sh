#!/bin/bash

# includes
. "/ARISU/scripts/error_handling.sh"

SCRIPT_NAME=$(/usr/bin/basename "${BASH_SOURCE[0]}")|| exit 100
FULL_PATH=$(/usr/bin/realpath "${BASH_SOURCE[0]}")|| exit 100
declare CACHE_DIR="/tmp/$SCRIPT_NAME/$YYYYMMDD"

if [ ! -d "$CACHE_DIR" ]; then
    /usr/bin/mkdir -p -v "$CACHE_DIR"|| exit 100
fi
trap '/bin/rm -rf "$CACHE_DIR"' INT TERM
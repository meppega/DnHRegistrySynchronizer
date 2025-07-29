#!/bin/bash

function message {
    message="$1"
    func_name="${2-unknown}"
    priority=6
    if [ -z "$2" ]; then
        echo "INFO:" "$message"
    else
        echo "ERROR:" "$message"
        priority=0
    fi
    /usr/bin/logger --journald<<EOF
MESSAGE_ID=$SCRIPT_NAME
MESSAGE=$message
PRIORITY=$priority
CODE_FILE=$FULL_PATH
CODE_FUNC=$func_name
EOF
}

function check_previous_run {
    local machine=$1
    test -f "$CACHE_DIR/$machine" && return 0|| return 1
}

function mark_previous_run {
    machine=$1
    /usr/bin/touch "$CACHE_DIR/$machine"
    return $?
}

# RUNNING="$(basename $0)"

# if [ "$RUNNING" = "error_handling" ]
# then
#     error_handling "$@"
# fi
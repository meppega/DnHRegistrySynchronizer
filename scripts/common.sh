#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e
# Treat unset variables as an error.
set -u
# The exit status of a pipeline is the exit status of the last command that failed.
set -o pipefail
# Associative array to map log levels to syslog priorities (RFC 5424)
declare -A LOG_PRIORITIES
LOG_PRIORITIES[EMERGENCY]=0  # system is unusable
LOG_PRIORITIES[ALERT]=1      # action must be taken immediately
LOG_PRIORITIES[CRITICAL]=2   # critical conditions
LOG_PRIORITIES[ERROR]=3      # error conditions
LOG_PRIORITIES[WARNING]=4    # warning conditions
LOG_PRIORITIES[NOTICE]=5     # normal but significant condition
LOG_PRIORITIES[INFO]=6       # informational messages
LOG_PRIORITIES[DEBUG]=7      # debug-level messages

# Define a default path to your log file.
: "${LOG_FILE:="/home/runner/arisu.log"}"

# Define a default name of your main script for MESSAGE_ID in journald.
: "${SCRIPT_NAME:=$(basename "${BASH_SOURCE[0]}")}" # Default if not set

# Define a default full path of your main script for CODE_FILE in journald.
: "${FULL_PATH:=$(readlink -f "${BASH_SOURCE[0]}")}"

# --- Internal Logging Helper ---

# _get_caller_func_name: Helper to determine the calling function's name.
# This is a robust way to get the function name, even if there are nested calls
# within the logging functions themselves. `caller 1` gives the function that called _log_message.
# Bash 3.x support: if `caller` is not available, it defaults to `unknown`.
_get_caller_func_name() {
    if command -v caller >/dev/null 2>&1; then
        caller 1 | awk '{print $2}' # Gets function name from 'caller' output
    else
        echo "unknown" # Fallback for older Bash or environments without 'caller'
    fi
}

# _log_message: Internal helper function for all log levels
# Arguments:
#   $1: Log level string (e.g., INFO, WARNING, ERROR, DEBUG). Case-insensitive.
#   $2: Message content.
#   $3 (optional): Explicit function name. If empty, _get_caller_func_name is used.
# Returns 1 if the level is ERROR or higher (CRITICAL, ALERT, EMERGENCY), 0 otherwise.
_log_message() {
    local level_raw="$1"
    local message_content="$2"
    local explicit_func_name="${3:-}" # Allow passing an explicit function name, otherwise it's empty

    # Convert level to uppercase for consistent lookup and display
    local level
    level=$(echo "$level_raw" | tr '[:lower:]' '[:upper:]')

    # Determine the function name for logging (explicitly provided or auto-detected)
    local func_name
    if [[ -n "$explicit_func_name" ]]; then
        func_name="$explicit_func_name"
    else
        func_name=$(_get_caller_func_name)
    fi

    # Get the journald priority, default to INFO (6) if level is invalid
    local journald_priority="${LOG_PRIORITIES[$level]:-${LOG_PRIORITIES[INFO]}}"

    # Format the timestamp and prefix for stdout/stderr and file logging
    # Using printf for more robust formatting.
    local timestamp
    timestamp=$(date +'%Y-%m-%d %H:%M:%S')
    local formatted_message="${timestamp} [${level}]: ${message_content}"

    # Print to stderr and tee to log file
    printf "%s\n" "$formatted_message" | tee -a "$LOG_FILE" >&2

    # Send to journald. Ensure SCRIPT_NAME and FULL_PATH are set in the main script.
    # Note: MESSAGE_ID and CODE_FILE should ideally reflect the *main* script,
    # so they are best initialized there and sourced/made global.
    # Assuming for this common.sh example that they are globally set before sourcing.
    /usr/bin/logger --journald --tag "${SCRIPT_NAME:-bash_script}" <<EOF
MESSAGE_ID=${SCRIPT_NAME:-unknown_script}
MESSAGE=${message_content}
PRIORITY=${journald_priority}
CODE_FILE=${FULL_PATH:-unknown_path}
CODE_FUNC=${func_name}
LOG_LEVEL=${level} # Add the explicit log level for journald querying
EOF

    # Return 1 if the level indicates an error (for convenience in calling scripts)
    case "$level" in
        ERROR|CRITICAL|ALERT|EMERGENCY)
            return 1
            ;;
        *)
            return 0
            ;;
    esac
}

# --- Public Logging Functions ---

# log_info: Logs an informational message.
# Arguments:
#   $1: Message content.
#   $2 (optional): Function name (defaults to auto-detected).
log_info() {
    _log_message "INFO" "$1" "${2:-}"
}

# log_warning: Logs a warning message.
# Arguments:
#   $1: Message content.
#   $2 (optional): Function name (defaults to auto-detected).
log_warning() {
    _log_message "WARNING" "$1" "${2:-}"
}

# log_error: Logs an error message and returns 1.
# Arguments:
#   $1: Message content.
#   $2 (optional): Function name (defaults to auto-detected).
log_error() {
    _log_message "ERROR" "$1" "${2:-}"
    return 1 # Explicitly return 1 for error functions
}

# log_debug: Logs a debug message.
# Arguments:
#   $1: Message content.
#   $2 (optional): Function name (defaults to auto-detected).
log_debug() {
    _log_message "DEBUG" "$1" "${2:-}"
}

# --- Trap Handler ---
# _err_trap_handler: Function to be executed on ERR signal.
# This provides more context for unexpected errors, logging where they occurred.
_err_trap_handler() {
    local last_command="${BASH_COMMAND}"
    local last_line="${BASH_LINENO[0]}" # Line number in the current script/function
    local last_source="${BASH_SOURCE[0]}" # File where the error occurred
    local current_function_stack=("${FUNCNAME[@]:1}") # Get function call stack, excluding the trap handler itself

    # Avoid infinite loop if logging itself fails
    if [[ "$last_command" == *log_* ]]; then
        echo "$(date +'%Y-%m-%d %H:%M:%S') [CRITICAL]: Error in trap handler or logger loop. Last command: '$last_command'." >&2
        exit 1
    fi

    local error_context="Command '$last_command' failed on line $last_line in '$last_source'."
    if [[ ${#current_function_stack[@]} -gt 0 ]]; then
        error_context+=" Function stack: '${current_function_stack[*]}'."
    fi

    # Log the error using the critical level
    _log_message "CRITICAL" "UNEXPECTED SCRIPT ERROR: $error_context" "_err_trap_handler"

    # Exit with a distinct error code for trap-caught errors, e.g., 255
    exit 255
}

# die: Logs a fatal error message and exits the script with status 1.
# Arguments:
#   $1: Message content.
#   $2 (optional): Function name (defaults to auto-detected).
die() {
    local message="$1"
    local func_name="${2:-}" # Pass optional func_name to log_error

    # Ensure this calls _log_message with the correct error level for journald
    _log_message "CRITICAL" "FATAL: $message" "${func_name:-$(_get_caller_func_name)}"
    exit 1
}

# --- General Utility Functions ---

# command_exists: Checks if a command exists in the system's PATH.
# Arguments:
#   $1: The command name to check.
# Returns 0 if the command exists, 1 otherwise.
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# file_exists_readable: Checks if a file exists and is readable.
# Arguments:
#   $1: The path to the file.
# Returns 0 if the file exists and is readable, 1 otherwise.
file_exists_readable() {
    local file_path="$1"
    [[ -f "$file_path" && -r "$file_path" ]]
}

# get_tgz_sha256: Calculates SHA256 digest of a .tgz file.
# Arguments:
#   $1: tgz_file (path to the tarball).
# Prints the SHA256 sum string to stdout on success, an empty string on failure.
# Returns 0 on success (SHA256 calculated or file not found), 1 if sha256sum command is missing.
get_tgz_sha256() {
    local tgz_file="$1"
    if [[ -f "$tgz_file" ]]; then
        if command_exists sha256sum; then
            sha256sum "$tgz_file" | awk '{print $1}' # Print result to stdout
            return 0 # Success
        else
            log_error "sha256sum command not found. Cannot calculate SHA256 for '$tgz_file'." "get_tgz_sha256"
            printf "" # indicate no hash
            return 1 # Indicate error
        fi
    else
        log_warning "File not found for SHA256 calculation: '$tgz_file'." "get_tgz_sha256"
        printf "" # Print empty string to stdout
        return 0 # Consider file not found a "success" in terms of no SHA being returned
    fi
}
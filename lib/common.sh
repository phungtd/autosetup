#!/bin/bash

# common.sh - Common utility functions for domain setup scripts
# This script provides common utility functions for domain setup scripts.

# Colors for better readability
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Script directory
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.."

# Create logs directory if it doesn't exist
mkdir -p "$LIB_DIR/logs"

# Log file
LOG_FILE="$LIB_DIR/logs/autosetup_$(date +%Y%m%d_%H%M%S).log"

# Install jq if not installed
command -v jq >/dev/null 2>&1 || {
    sudo apt-get install -y jq >/dev/null 2>&1 ||
        sudo yum install -y jq >/dev/null 2>&1 ||
        sudo dnf install -y jq >/dev/null 2>&1 ||
        sudo pacman -S --noconfirm jq >/dev/null 2>&1 ||
        sudo apk add jq >/dev/null 2>&1
}

# Check if jq is installed
if ! command -v jq >/dev/null 2>&1; then
    log_error "jq is not installed"
    exit 1
fi

# Function to get user input with a prompt and default value
get_input() {
    # Input parameters
    local prompt="$1"
    local default="$2"
    local input

    echo >&2

    # Check if prompt is provided
    if [ -z "$prompt" ]; then
        log_error "Prompt is required"
        return 1
    fi

    # If default value provided, show it in prompt
    if [ -n "$default" ]; then
        read -e -r -p "${prompt} [${default}]: " input
        echo "${input:-$default}"
    else
        read -e -r -p "${prompt}: " input
        echo "$input"
    fi
}

# Function to get yes/no input with default
get_yes_no() {
    # Input parameters
    local prompt="$1"
    local default="$2"

    # Return value
    local result=""

    # Check if prompt is provided
    if [ -z "$prompt" ]; then
        log_error "Prompt is required"
        return 1
    fi

    # Format prompt based on default
    if [ "$default" = "yes" ] || [ "$default" = "y" ]; then
        read -e -r -p "$prompt [Y/n]: " result
        result=${result:-y}
    else
        read -e -r -p "$prompt [y/N]: " result
        result=${result:-n}
    fi

    # Return value
    case "$result" in
    [Yy]*)
        echo "yes"
        ;;
    *)
        echo "no"
        ;;
    esac
}

# Function to generate a random password
generate_password() {
    local length="${1:-16}"
    local charset="A-Za-z0-9"

    # Validate length is a positive number
    if ! [[ "$length" =~ ^[0-9]+$ ]] || [ "$length" -lt 1 ]; then
        log_error "Invalid password length: $length"
        return 1
    fi

    tr -dc "$charset" </dev/urandom | head -c "$length"
}

# Function to get server's public IP
get_server_ip() {
    # Return value
    local ip

    # Try multiple services in case one is down
    ip=$(curl -s ifconfig.me 2>/dev/null ||
        curl -s icanhazip.com 2>/dev/null ||
        curl -s ipecho.net/plain 2>/dev/null)

    if [ -z "$ip" ]; then
        log_error "Failed to determine server IP"
        return 1
    fi

    log_success "Got server IP: $ip"

    echo "$ip"
    return 0
}

# Function to load configuration
load_config() {
    # Config file path
    local config_file="$LIB_DIR/config/config.ini"
    chmod 600 "${config_file}"

    # Section tracking
    local current_section

    # Key-value variables
    local key
    local value

    if [ ! -f "$config_file" ]; then
        log_warning "Configuration file not found: $config_file"
        return 1
    fi

    # Parse the config file
    while IFS='=' read -r key value; do
        # Skip comments and empty lines
        [[ $key =~ ^[[:space:]]*[#\;] ]] && continue
        [[ -z "$key" ]] && continue

        # Trim whitespace
        key=$(echo "$key" | xargs)
        value=$(echo "$value" | xargs)

        # Set variable with section prefix
        if [[ $key == \[*] ]]; then
            # This is a section header
            current_section=$(echo "$key" | tr -d '[]')
        else
            # This is a key-value pair
            if [ -n "$current_section" ]; then
                eval "cfg_${current_section}_${key}=\"$value\""
            else
                eval "cfg_${key}=\"$value\""
            fi
        fi
    done <"$config_file"

    return 0
}

# Logging functions
log_debug() {
    local message="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [DEBUG] $message" >>"$LOG_FILE"
}

log_info() {
    local message="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $message" >>"$LOG_FILE"
    echo -e "$message" >&2
}

log_warning() {
    local message="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARNING] $message" >>"$LOG_FILE"
    echo -e "${YELLOW}$message${NC}" >&2
}

log_error() {
    local message="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $message" >>"$LOG_FILE"
    echo -e "${RED}$message${NC}" >&2
}

log_success() {
    local message="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [SUCCESS] $message" >>"$LOG_FILE"
    echo -e "${GREEN}$message${NC}" >&2
}

# Function to make HTTP requests
make_request() {
    # Input parameters
    local url="${1}"
    local method="${2:-GET}"
    local data="${3}"
    local headers="${4}"
    local cmd
    local masked_url
    local result

    # Mask sensitive information in URL
    masked_url="${url//$NAMECHEAP_API_KEY/[API_KEY_HIDDEN]}"
    log_info "Making $method request to $masked_url"

    # Check if URL is provided
    if [ -z "$url" ]; then
        log_error "URL is required"
        return 1
    fi

    # Build curl command with proper quoting
    cmd=("curl" "-k" "-X" "${method}")

    # Add headers if provided

    if [ -n "${headers}" ]; then
        IFS='|' read -ra headers_array <<<"$headers"
        for header in "${headers_array[@]}"; do
            cmd+=("-H" "'${header}'")
        done
    fi

    # Add data if provided
    if [ -n "${data}" ]; then
        cmd+=("-d" "'${data}'")
    fi

    # Add URL
    cmd+=("'${url}'")

    log_debug "Executing: ${cmd[*]}"

    # Execute command safely using array
    if ! result=$(eval "${cmd[*]}" 2>/dev/null); then
        log_error "Request failed"
        return 1
    fi

    echo "${result}"
    return 0
}

# Function to URL encode a string
url_encode() {
    # Input parameters
    local string="$1"

    # String processing variables
    local strlen=${#string}
    local encoded=""
    local c
    local i

    for ((i = 0; i < strlen; i++)); do
        c="${string:$i:1}"
        if [[ "$c" =~ [a-zA-Z0-9._~-] ]]; then
            encoded+="$c"
        else
            encoded+="%$(printf '%02X' "'$c")"
        fi
    done
    echo "${encoded}"
}

# Function to check if domain resolves and responds
verify_domain_ping() {
    # Input parameters
    local domain="$1"
    local expected_ip="$2"

    # Response variables
    local resolved_ip

    # Check if domain name and expected IP are provided
    if [ -z "$domain" ] || [ -z "$expected_ip" ]; then
        log_error "Domain name and expected IP are required"
        return 1
    fi

    # Try ping first (2 attempts, 1 second timeout)
    if ping -c 2 -W 1 "$domain" >/dev/null 2>&1; then
        # Get the IP that actually responded
        resolved_ip=$(ping -c 1 -W 1 "$domain" | head -n1 | grep -oP '\(\K[^\)]+')
        if [ "$resolved_ip" == "$expected_ip" ]; then
            log_info "Domain $domain pings successfully to $expected_ip"
            return 0
        else
            log_info "Domain $domain resolves to $resolved_ip (expected $expected_ip)"
        fi
    else
        log_info "Domain $domain does not respond to ping"
    fi

    return 1
}

# Function to verify domain connectivity with retry
verify_domain_loop() {
    # Input parameters
    local domain="$1"
    local expected_ip="$2"
    local max_attempts="${3:-30}" # Default to 30 attempts
    local wait_time="${4:-60}"    # Default to 60 seconds between attempts

    # Check if domain name and expected IP are provided
    if [ -z "$domain" ] || [ -z "$expected_ip" ]; then
        log_error "Domain name and expected IP are required"
        return 1
    fi

    # Loop variables
    local attempt=1
    while [ $attempt -le "${max_attempts}" ]; do
        if verify_domain_ping "$domain" "$expected_ip"; then
            return 0
        fi

        if [ $attempt -lt "${max_attempts}" ]; then
            log_info "$attempt / $max_attempts: Domain not responding correctly yet. Waiting ${wait_time} seconds..."
            sleep "${wait_time}"
        fi
        attempt=$((attempt + 1))
    done

    return 1
}

# Function to verify domain propagation
verify_domain_propagation() {
    # Input parameters
    local domain="$1"
    local expected_ip="$2"
    local max_attempts="${3:-30}"
    local wait_time="${4:-60}"

    # Check if domain name and expected IP are provided
    if [ -z "$domain" ] || [ -z "$expected_ip" ]; then
        log_error "Domain name and expected IP are required"
        return 1
    fi

    log_info "Verifying connectivity for $domain, expecting IP: $expected_ip, every ${wait_time}s, max ${max_attempts} attempts"

    if verify_domain_loop "$domain" "$expected_ip" "${max_attempts}" "${wait_time}"; then
        log_success "Domain verification successful"
        return 0
    else
        log_error "Domain verification failed"
        return 1
    fi
}

# Load configuration on script start
load_config

# Ensure we can write to the log file
touch "$LOG_FILE" 2>/dev/null || {
    echo -e "${RED}Error: Cannot write to log file $LOG_FILE${NC}"
    exit 1
}

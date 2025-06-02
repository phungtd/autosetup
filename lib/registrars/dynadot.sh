#!/bin/bash

# dynadot.sh - Dynadot API Implementation
# This script provides functions to interact with Dynadot using the API.

# Configuration variables
DYNADOT_API_KEY="${cfg_dynadot_api_key:-}"
DYNADOT_API_URL="${cfg_dynadot_api_endpoint:-https://api.dynadot.com/api3.json}"

# Check if API credentials are available
if [ -z "$DYNADOT_API_KEY" ]; then
    log_warning "Dynadot API key not found in configuration"

    # Prompt for credentials
    DYNADOT_API_KEY=$(get_input "Dynadot API Key" "")

    if [ -z "$DYNADOT_API_KEY" ]; then
        log_error "Dynadot API Key is required"
        exit 1
    fi
fi

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

# Function to make API calls to Dynadot
dynadot_api_call() {
    # Input parameters
    local endpoint="$1"
    local params="$2"
    local method="${3:-GET}"

    # API variables
    local api_key="${DYNADOT_API_KEY}"
    local api_url="${DYNADOT_API_URL}"
    local response
    local exit_code

    log_info "Making Dynadot API call: ${endpoint}"

    # Check if endpoint is provided
    if [ -z "$endpoint" ]; then
        log_error "Endpoint is required"
        return 1
    fi

    # Build request URL
    local url="${api_url}?key=${api_key}&command=${endpoint}"
    if [ -n "$params" ]; then
        url="${url}&${params}"
    fi

    # Make API request
    response=$(make_request "$url" "$method")
    exit_code=$?

    if [ $exit_code -ne 0 ]; then
        log_error "API request failed"
        return 1
    fi

    # Log the response
    if [ -n "${response}" ]; then
        log_debug "Response: ${response}"
    fi

    # Check if response is valid JSON
    if ! echo "$response" | jq empty >/dev/null 2>&1; then
        log_error "Invalid JSON response from Dynadot API"
        return 1
    fi

    echo "$response"
    return ${exit_code}
}

# Function to parse error from Dynadot API response
dynadot_parse_error() {
    # Input parameters
    local response="$1"

    # Response variables
    local response_code
    local error_msg

    # Check if response has valid SearchResponse format
    if ! echo "$response" | jq -e '[.[].ResponseCode] | first' >/dev/null 2>&1; then
        echo "Unexpected response format"
        return 1
    fi

    # Check for error response
    if response_code=$(echo "$response" | jq -r '[.[].ResponseCode] | first // empty'); then
        if [ "$response_code" = "0" ]; then
            return 0 # No error found
        else
            # if [ "$response_code" = "-1" ]; then
            error_msg=$(echo "$response" | jq -r '[.[].Status] | first // empty')
            error_msg+=" "
            error_msg+=$(echo "$response" | jq -r '[.[].Error] | first // empty')
            echo "$error_msg" | xargs
            return 1 # Error found
            # fi
        fi
    fi
}

# Function to parse search results from API response
dynadot_parse_search_results() {
    # Input parameters
    local response="$1"

    # Parse variables
    local results=""
    local domain status available error code message

    log_info "Parsing search results"

    # Check if response has valid SearchResponse format
    if ! echo "$response" | jq -e '.SearchResponse.SearchResults' >/dev/null 2>&1; then
        echo "Unexpected response format"
        return 1
    fi

    # Process each search result
    while IFS= read -r result; do
        # Extract fields using jq
        domain=$(echo "$result" | jq -r '.DomainName')
        status=$(echo "$result" | jq -r '.Status')
        available=$(echo "$result" | jq -r '.Available // empty')
        error=$(echo "$result" | jq -r '.Error // empty')

        # Determine code and message based on status and availability
        if [ "$status" = "success" ]; then
            if [ "$available" = "yes" ]; then
                code=0
                message="Domain $domain is available"
            elif [ "$available" = "no" ]; then
                code=1
                message="Domain $domain is not available"
            else
                code=2
                message="Unexpected response format"
            fi
        elif [ "$status" = "error" ]; then
            code=1
            message="Error: $error"
        else
            code=2
            message="Invalid status: $status"
        fi

        # Add result to output
        if [ -n "$results" ]; then
            results="${results}\n"
        fi
        results="${results}${domain}|${code}|${message}"
    done < <(echo "$response" | jq -c '.SearchResponse.SearchResults[]')

    # Output results
    echo -e "$results"
    return 0
}

# Function to check domain availability
dynadot_check_availability() {
    # Input parameters
    local domain="$1"

    # Response variables
    local response
    local results
    local error_msg
    local code
    local message
    local domain_result

    log_info "Checking availability of domain: $domain"

    # Check if domain name is provided
    if [ -z "$domain" ]; then
        log_error "Domain name is required"
        return 1
    fi

    # Make API call
    response=$(dynadot_api_call "search" "domain0=${domain}")

    # Check for API errors first
    if ! error_msg=$(dynadot_parse_error "$response"); then
        log_error "Dynadot API error: $error_msg"
        return 2
    fi

    # Parse search results
    if ! results=$(dynadot_parse_search_results "$response"); then
        log_error "Failed to parse search results: $results"
        return 2
    fi

    # Find the specific domain result
    domain_result=$(echo "$results" | grep "^${domain}|")
    if [ -z "$domain_result" ]; then
        log_error "No result found for domain: $domain"
        return 2
    fi

    # Extract code and message for the domain
    code=$(echo "$domain_result" | cut -d'|' -f2)
    message=$(echo "$domain_result" | cut -d'|' -f3)

    # Log appropriate message
    case $code in
    0)
        log_success "$message"
        return 0
        ;;
    1)
        log_error "$message"
        return 1
        ;;
    *)
        log_error "$message"
        return 2
        ;;
    esac
}

# Function to get domain information
dynadot_get_domain_info() {
    # Input parameters
    local domain="$1"

    # Response variables
    local response
    local error_msg
    local info
    local expiration_ms
    local registration_ms

    log_info "Getting domain info for: $domain"

    # Check if domain name is provided
    if [ -z "$domain" ]; then
        log_error "Domain name is required"
        return 1
    fi

    # Make API call
    response=$(dynadot_api_call "domain_info" "domain=${domain}")

    # Check for API errors
    if ! error_msg=$(dynadot_parse_error "$response"); then
        log_error "Failed to get domain info: $error_msg"
        return 1
    fi

    # Check if we got a valid response with domain info
    if ! echo "$response" | jq -e '.DomainInfoResponse.DomainInfo' >/dev/null 2>&1; then
        log_error "No domain info found in response"
        return 1
    fi

    # Extract domain info
    info=$(echo "$response" | jq -r '.DomainInfoResponse.DomainInfo')

    # Convert timestamps to readable dates
    expiration_ms=$(echo "$info" | jq -r '.Expiration // empty')
    registration_ms=$(echo "$info" | jq -r '.Registration // empty')

    # Print domain information
    echo "Domain Information for $domain:"
    echo "--------------------------------"
    if [ -n "$expiration_ms" ]; then
        echo "Expiration: $(date -d "@$((expiration_ms / 1000))" "+%Y-%m-%d")"
    fi
    if [ -n "$registration_ms" ]; then
        echo "Registration: $(date -d "@$((registration_ms / 1000))" "+%Y-%m-%d")"
    fi
    echo "Nameserver Type: $(echo "$info" | jq -r '.NameServerSettings.Type // "N/A"')"
    echo "Is Locked: $(echo "$info" | jq -r '.Locked // "N/A"')"
    echo "Is Disabled: $(echo "$info" | jq -r '.Disabled // "N/A"')"
    echo "UDRP Locked: $(echo "$info" | jq -r '.UdrpLocked // "N/A"')"
    echo "Privacy: $(echo "$info" | jq -r '.Privacy // "N/A"')"
    echo "For Sale: $(echo "$info" | jq -r '.isForSale // "N/A"')"
    echo "Renew Option: $(echo "$info" | jq -r '.RenewOption // "N/A"')"
    echo "Folder: $(echo "$info" | jq -r '.Folder.FolderName // "N/A"')"
    echo "--------------------------------"

    # Return success
    return 0
}

# Function to check if domain is owned
dynadot_is_domain_owned() {
    # Input parameters
    local domain="$1"

    # Response variables
    local response
    local error_msg
    local domain_name

    log_info "Checking if domain is owned: $domain"

    # Check if domain name is provided
    if [ -z "$domain" ]; then
        log_error "Domain name is required"
        return 1
    fi

    # Make API call
    response=$(dynadot_api_call "domain_info" "domain=${domain}")

    # Check for API errors
    if ! error_msg=$(dynadot_parse_error "$response"); then
        log_error "Failed to check domain ownership: $error_msg"
        return 1
    fi

    # Check if we got a valid response with domain info
    if ! echo "$response" | jq -e '.DomainInfoResponse.DomainInfo' >/dev/null 2>&1; then
        log_error "Domain not owned: No domain info found"
        return 1
    fi

    # Check if the domain name matches
    domain_name=$(echo "$response" | jq -r '.DomainInfoResponse.DomainInfo.Name // empty')
    if [ "$domain_name" = "$domain" ]; then
        log_success "Domain $domain is owned by the current user"
        return 0
    else
        log_error "Domain not owned, name mismatch ($domain_name != $domain)"
        return 1
    fi
}

# Function to purchase domain
registrar_purchase_domain() {
    # Input parameters
    local domain="$1"
    local duration="${2:-1}"

    # Response variables
    local response
    local error_msg
    local status
    local expiration

    log_info "Purchasing domain: $domain"

    # Check if domain name is provided
    if [ -z "$domain" ]; then
        log_error "Domain name is required"
        return 1
    fi

    # Check if domain is already owned
    if dynadot_is_domain_owned "$domain"; then
        return 0
    fi

    # Check if domain is available first
    # if ! dynadot_check_availability "$domain"; then
    #     return 1
    # fi

    # Build registration parameters (only required ones)
    local params="domain=${domain}&duration=${duration}"

    # Make API call
    response=$(dynadot_api_call "register" "$params")

    # Check for API errors
    if ! error_msg=$(dynadot_parse_error "$response"); then
        log_error "Failed to purchase domain: $error_msg"
        return 1
    fi

    # Extract order ID if available
    status=$(echo "$response" | jq -r '.RegisterResponse.Status // empty')
    if [ "$status" = "success" ]; then
        expiration=$(echo "$response" | jq -r '.RegisterResponse.Expiration // empty')
        seconds=$((expiration / 1000))
        log_success "Domain $domain purchased successfully. Expiration date: $(date -d "@$seconds" +%Y-%m-%d)"
        return 0
    else
        log_error "Failed to purchase domain: $status"
        return 1
    fi
}

# Function to configure DNS
registrar_configure_dns() {
    # Input parameters
    local domain="$1"
    local server_ip="$2"

    # Response variables
    local response
    local error_msg
    local exit_code=0

    log_info "Configuring DNS for domain: $domain to point to IP: $server_ip"

    # Check required parameters
    if [ -z "$domain" ] || [ -z "$server_ip" ]; then
        log_error "Domain name and server IP are required"
        return 1
    fi

    # First set nameservers
    # log_info "Setting nameservers for $domain"
    # local ns_params="domain=${domain}"
    # ns_params+="&ns0=ns1.dyna-ns.net"
    # ns_params+="&ns1=ns2.dyna-ns.net"

    # response=$(dynadot_api_call "set_ns" "$ns_params")
    # if ! error_msg=$(dynadot_parse_error "$response"); then
    #     log_error "Failed to set nameservers: $error_msg"
    #     exit_code=1
    # else
    #     log_success "Nameservers set successfully"
    # fi

    # Then configure DNS records
    log_info "Configuring DNS records for $domain"
    local dns_params="domain=${domain}"
    dns_params+="&main_record_type0=a"
    dns_params+="&main_record0=${server_ip}"
    dns_params+="&subdomain0=www"
    dns_params+="&sub_record_type0=cname"
    dns_params+="&sub_record0=@"

    response=$(dynadot_api_call "set_dns2" "$dns_params")
    if ! error_msg=$(dynadot_parse_error "$response"); then
        log_error "Failed to configure DNS records: $error_msg"
        exit_code=1
    else
        log_success "DNS records configured successfully"
    fi

    return $exit_code
}

log_info "Dynadot API module loaded"

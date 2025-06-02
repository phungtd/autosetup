#!/bin/bash

# cyberpanel.sh - CyberPanel CLI Implementation
# This script provides functions to interact with CyberPanel using the CLI.

# Configuration variables
CYBERPANEL_API_URL="https://${cfg_server_ip:-$(get_server_ip)}:8090/api"

# Function to check if CyberPanel is installed
cyberpanel_check_installed() {
    log_info "Checking if CyberPanel is installed"

    # Check if cyberpanel command exists and is executable
    if ! command -v cyberpanel &>/dev/null; then
        log_error "CyberPanel CLI command not found"
        return 1
    fi

    log_success "CyberPanel installation found"
    return 0
}

# Function to verify CyberPanel connection
cyberpanel_verify_connection() {
    # API request variables
    local data="{\"adminUser\":\"admin\",\"adminPass\":\"test\"}"
    local headers="Content-Type: application/json"
    local response

    log_info "Verifying CyberPanel connection"

    # Make API request
    response=$(make_request "${CYBERPANEL_API_URL}/verifyConn" "POST" "$data" "$headers")
    log_debug "Response: $response"

    # Check response
    if [ -n "$response" ] && echo "$response" | grep -q '"verifyConn": *0'; then
        log_success "CyberPanel connection verified"
        return 0
    else
        log_error "CyberPanel connection failed"
        return 1
    fi
}

# Function to get installed PHP versions
cyberpanel_get_php_versions() {
    # Version collection variables
    local versions=()
    local version
    local versions_sorted
    local php_path

    # Collect PHP versions
    for php_path in /usr/local/lsws/lsphp*/bin/php; do
        if [ -x "$php_path" ]; then
            version=$($php_path -v | head -n1 | cut -d' ' -f2 | cut -d'.' -f1,2)
            versions+=("$version")
        fi
    done

    # Sort versions in descending order
    versions_sorted=$(echo "${versions[@]}" | tr ' ' '\n' | sort -V | tr '\n' ' ')
    log_debug "PHP versions: $versions_sorted"

    echo "$versions_sorted"
}

# Function to run cyberpanel command and log output
cyberpanel_run() {
    # Command variables
    local cmd="$1"
    local output
    local exit_code
    local password_part
    local password_hidden

    # Check if command is provided
    if [ -z "$cmd" ]; then
        log_error "Command is required"
        return 1
    fi

    # Extract and hide password if present
    password_part=$(echo "$cmd" | grep -o -- '--dbPassword [^[:space:]]*')
    if [[ -n "$password_part" ]]; then
        password_hidden="${cmd//$password_part/--dbPassword [PASSWORD_HIDDEN]}"
        log_info "Executing: cyberpanel $password_hidden"
    else
        log_info "Executing: cyberpanel $cmd"
    fi

    # Run command and capture output
    output=$(cyberpanel $cmd 2>&1)
    exit_code=$?

    # Log the command output
    if [ -n "$output" ]; then
        log_debug "Response: $output"
    fi

    # Return the output and preserve exit code
    echo "$output"
    return $exit_code
}

# Function to parse error message from command response
cyberpanel_parse_error_message() {
    local response="$1"
    echo "$response" | grep -o '"errorMessage": *"[^"]*"' | cut -d':' -f2 | tr -d '"' | xargs
}

# Function to parse success message from command response
cyberpanel_parse_success_message() {
    local response="$1"
    echo "$response" | grep -q '"success": *1' && echo "true" || echo "false"
}

# Function to set up SSL certificate
panel_setup_ssl() {
    # Input parameters
    local domain="$1"

    # Command execution variables
    local cmd
    local result
    local success
    local error

    log_info "Setting up SSL certificate for domain: $domain"

    # Check if domain name is provided
    if [ -z "$domain" ]; then
        log_error "Domain name is required"
        return 1
    fi

    # Issue SSL using CLI
    cmd="issueSSL --domainName $domain"
    result=$(cyberpanel_run "$cmd")
    success=$(cyberpanel_parse_success_message "$result")
    error=$(cyberpanel_parse_error_message "$result")

    # Check if command was successful
    if [ "$success" == "true" ] && [ "$error" == "None" ]; then
        log_success "SSL certificate issued successfully for $domain"
        return 0
    else
        log_error "Failed to issue SSL certificate: $error"
        return 1
    fi
}

# Function to list websites in JSON format
cyberpanel_list_websites() {
    # Response variables
    local response
    local exit_code

    log_info "Getting list of websites from CyberPanel"

    # Make API call
    response=$(cyberpanel_run "listWebsitesJson")
    exit_code=$?

    if [ $exit_code -ne 0 ]; then
        log_error "Failed to get website list"
        return 1
    fi

    echo "$response"
    return 0
}

# Function to parse website list JSON
cyberpanel_parse_websites() {
    # Input parameters
    local json_input="$1"

    # Check if jq is available
    if command -v jq >/dev/null 2>&1; then
        # Use jq for proper JSON parsing
        echo "$json_input" | jq -r '.[] | "\(.domain)|\(.adminEmail)|\(.ipAddress)|\(.state)"'
    else
        # Fallback to basic parsing if jq is not available
        echo "$json_input" | grep -o '"domain":"[^"]*"' | cut -d'"' -f4
    fi
}

# Function to delete a website
cyberpanel_delete_website() {
    # Input parameters
    local domain="$1"

    # Response variables
    local response
    local exit_code

    log_info "Deleting website: $domain"

    if [ -z "$domain" ]; then
        log_error "Domain name is required for deletion"
        return 1
    fi

    # Make API call
    response=$(cyberpanel_run "deleteWebsite --domainName $domain")
    exit_code=$?

    if [ $exit_code -ne 0 ]; then
        log_error "Failed to delete website: $domain"
        return 1
    fi

    log_success "Successfully deleted website: $domain"
    return 0
}

# Function to delete multiple websites
cyberpanel_delete_websites() {
    # Input parameters
    local websites="$1"

    # Loop variables
    local domain
    local count=0
    local total=0
    local failed=0

    log_info "Starting bulk website deletion"

    # Check if websites are provided
    if [ -z "$websites" ]; then
        log_error "Websites are required"
        return 1
    fi

    # Count total websites
    total=$(echo "$websites" | wc -l)

    # Process each website
    while IFS='|' read -r domain _email _ip _state; do
        count=$((count + 1))
        log_info "Processing ($count/$total): $domain"

        if ! cyberpanel_delete_website "$domain"; then
            failed=$((failed + 1))
        fi

        # Add a small delay to prevent overwhelming the server
        sleep 1
    done < <(echo "$websites")

    # Summary
    log_info "Bulk deletion completed. Total: $total, Failed: $failed"
    return $failed
}

# Function to create website
panel_create_website() {
    # Input parameters
    local domain="$1"

    # PHP version selection variables
    local php_versions
    local selected_php
    local choice
    local i

    # Command execution variables
    local cmd
    local email
    local result
    local success
    local error

    log_info "Creating website for domain: $domain"

    # Check if domain name is provided
    if [ -z "$domain" ]; then
        log_error "Domain name is required"
        return 1
    fi

    # Get available PHP versions
    read -ra php_versions <<<"$(cyberpanel_get_php_versions)"

    if [ ${#php_versions[@]} -eq 0 ]; then
        log_error "No PHP versions found"
        return 1
    fi

    # Let user choose PHP version
    echo -e "\nAvailable PHP versions:\n" >&2
    for i in "${!php_versions[@]}"; do
        echo "$((i + 1)). PHP ${php_versions[$i]}" >&2
    done

    while true; do
        choice=$(get_input "Select PHP version (1-${#php_versions[@]})" "")

        # Validate input
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#php_versions[@]}" ]; then
            selected_php="${php_versions[$((choice - 1))]}"
            break
        else
            echo -e "${RED}Invalid selection${NC}" >&2
        fi
    done

    log_info "Using PHP version $selected_php"

    # Create website using CLI with selected PHP version
    email="${cfg_defaults_email:-admin@$domain}"
    cmd="createWebsite --package Default --owner admin --domainName $domain --email $email --php $selected_php"
    result=$(cyberpanel_run "$cmd")
    success=$(cyberpanel_parse_success_message "$result")
    error=$(cyberpanel_parse_error_message "$result")

    # Check if command was successful
    if [ "$success" == "true" ]; then
        log_success "Website created successfully for $domain with PHP $selected_php"
        return 0
    else
        log_error "Failed to create website: $error"
        return 1
    fi
}

# Function to create database
panel_create_database() {
    # Input parameters
    local domain="$1"
    local db_pass="$2"

    # Database variables
    local db_name="${domain//[.-]/}"
    local db_user="$db_name"

    # Command execution variables
    local cmd
    local result
    local success
    local error

    log_info "Creating database: $db_name with user: $db_user"

    # Check if domain name is provided
    if [ -z "$domain" ]; then
        log_error "Domain name is required"
        return 1
    fi

    # Check if database password is provided
    if [ -z "$db_pass" ]; then
        log_error "Database password is required"
        return 1
    fi

    # Create database using CLI
    cmd="createDatabase --databaseWebsite $domain --dbName $db_name --dbUsername $db_user --dbPassword $db_pass"
    result=$(cyberpanel_run "$cmd")
    success=$(cyberpanel_parse_success_message "$result")
    error=$(cyberpanel_parse_error_message "$result")

    # Check if command was successful - need both "success": 1 AND "errorMessage": "None"
    if [ "$success" == "true" ] && [ "$error" == "None" ]; then
        log_success "Database $db_name created successfully"
        return 0
    else
        log_error "Failed to create database: $error"
        return 1
    fi
}

# Check if CyberPanel is installed
if ! cyberpanel_check_installed; then
    exit 1
fi

# Verify CyberPanel connection
if ! cyberpanel_verify_connection; then
    exit 1
fi

log_info "CyberPanel CLI module loaded"

#!/bin/bash

# autosetup.sh - Automated Domain Purchase and Website Setup
# This script automates purchasing domains, DNS configuration, and website setup.

# Set script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load common functions
# shellcheck source=/dev/null
source "$SCRIPT_DIR/lib/common.sh"

# Load sources functions
# shellcheck source=/dev/null
source "$SCRIPT_DIR/lib/sources.sh"

# Default values
cfg_default_nameserver="${cfg_defaults_nameserver:-namecheap}"
cfg_default_panel="${cfg_defaults_panel:-cyberpanel}"

# Function to display usage information
usage() {
    echo -e "${BLUE}Usage:${NC} $0 [options]"
    echo
    echo "All parameters are optional. If not provided, you will be prompted interactively."
    echo
    echo "Optional arguments:"
    echo "  --domain DOMAIN           Domain name to purchase and set up"
    echo "  --source SOURCE           Source to use (bk8 or ...)"
    echo "  --nameserver PROVIDER     Domain registrar to use (namecheap or dynadot)"
    echo "  --panel PANEL             Panel to use (cyberpanel or ...)"
    echo
    echo "Control options:"
    echo "  --skip-domain             Skip domain purchase"
    echo "  --skip-dns                Skip DNS configuration"
    echo "  --skip-web                Skip website creation"
    echo "  --skip-ssl                Skip SSL certificate setup"
    echo "  --skip-db                 Skip database creation"
    echo "  --skip-wp                 Skip WordPress installation"
    echo "  --help                    Display this help message"
    exit 1
}

# Command line arguments
arg_domain=""
arg_source=""
arg_nameserver=""
arg_panel=""
arg_skip_domain="false"
arg_skip_dns="false"
arg_skip_web="false"
arg_skip_ssl="false"
arg_skip_db="false"
arg_skip_wp="false"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    key="${1}"
    case ${key} in
    --domain)
        arg_domain="${2}"
        shift 2
        ;;
    --source)
        arg_source="${2}"
        shift 2
        ;;
    --nameserver)
        arg_nameserver="${2}"
        shift 2
        ;;
    --panel)
        arg_panel="${2}"
        shift 2
        ;;
    --skip-domain)
        arg_skip_domain="true"
        shift
        ;;
    --skip-dns)
        arg_skip_dns="true"
        shift
        ;;
    --skip-web)
        arg_skip_web="true"
        shift
        ;;
    --skip-ssl)
        arg_skip_ssl="true"
        shift
        ;;
    --skip-db)
        arg_skip_db="true"
        shift
        ;;
    --skip-wp)
        arg_skip_wp="true"
        shift
        ;;
    --help)
        usage
        ;;
    *)
        echo -e "${RED}Unknown option: ${key}${NC}"
        usage
        ;;
    esac
done

# Print welcome message
echo
echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}      Domain Purchase & Website Setup       ${NC}"
echo -e "${BLUE}============================================${NC}"
echo
echo -e "${YELLOW}Press Enter to accept default values${NC}"
echo

# Get domain if not provided
if [ -z "${arg_domain}" ]; then
    while [ -z "${arg_domain}" ]; do
        arg_domain=$(get_input "Domain name" "")
        if [ -z "${arg_domain}" ]; then
            echo -e "${RED}Error: Domain name is required${NC}"
        fi
    done
else
    echo -e "Domain name: ${GREEN}${arg_domain}${NC}"
fi

# Get nameserver if not provided
if [ -z "${arg_nameserver}" ]; then
    arg_nameserver=$(get_input "Domain registrar" "${cfg_default_nameserver}")
else
    echo -e "Domain registrar: ${GREEN}${arg_nameserver}${NC}"
fi

# Get control panel if not provided
if [ -z "${arg_panel}" ]; then
    arg_panel=$(get_input "Control panel" "${cfg_default_panel}")
else
    echo -e "Control panel: ${GREEN}${arg_panel}${NC}"
fi

# Get source if not provided and handle source download
source_url=$(get_source_url "${arg_source}")
exit_code=$?
source_file=""
if [ "$exit_code" -eq 0 ] && [ -n "$source_url" ]; then
    echo -e "\nWordPress source: ${source_url}"
    if ! source_file=$(download_source "$source_url"); then
        exit 1
    fi
else
    exit 1
fi

echo
echo -e "${BLUE}Loading modules...${NC}"
echo

# Server IP variable
cfg_server_ip=""
if ! cfg_server_ip=$(get_server_ip); then
    exit 1
fi

# Load panel module
panel_file="${SCRIPT_DIR}/lib/panels/${arg_panel}.sh"

if [[ -f "$panel_file" ]]; then
    # shellcheck source=/dev/null
    source "$panel_file"
else
    log_error "Unsupported panel: ${arg_panel}"
    exit 1
fi

# Load registrar module based on selection
registrar_file="${SCRIPT_DIR}/lib/registrars/${arg_nameserver}.sh"

if [[ -f "$registrar_file" ]]; then
    # shellcheck source=/dev/null
    source "$registrar_file"
else
    log_error "Unsupported registrar: ${arg_nameserver}"
    exit 1
fi

# Auto-generate database information from domain
cfg_db_name="${arg_domain//[.-]/}"
cfg_db_user="${arg_domain//[.-]/}"
# cfg_db_user="${cfg_db_user}_$(date +%m%d)"

# Generate a random password
cfg_db_pass=$(generate_password 16)

# Display summary
echo
echo -e "${BLUE}Summary of settings...${NC}"
echo
echo -e "Domain    : ${GREEN}${arg_domain}${NC}"
echo -e "Registrar : ${GREEN}${arg_nameserver}${NC}"
echo -e "Panel     : ${GREEN}${arg_panel}${NC}"

if [ "${arg_skip_db}" != "true" ]; then
    echo -e "DB Name   : ${GREEN}${cfg_db_name}${NC}"
    echo -e "DB User   : ${GREEN}${cfg_db_user}${NC}"
    echo -e "DB Pass   : ${GREEN}${cfg_db_pass}${NC} (auto-generated)"
fi

echo -e "WP Source : ${GREEN}${source_url}${NC}"

if [ "${arg_skip_domain}" = "true" ]; then
    echo -e "Skip domain purchase: ${YELLOW}Yes${NC}"
fi

if [ "${arg_skip_dns}" = "true" ]; then
    echo -e "Skip DNS configuration: ${YELLOW}Yes${NC}"
fi

if [ "${arg_skip_web}" = "true" ]; then
    echo -e "Skip website creation: ${YELLOW}Yes${NC}"
fi

if [ "${arg_skip_ssl}" = "true" ]; then
    echo -e "Skip SSL setup: ${YELLOW}Yes${NC}"
fi

if [ "${arg_skip_db}" = "true" ]; then
    echo -e "Skip database creation: ${YELLOW}Yes${NC}"
fi
if [ "${arg_skip_wp}" = "true" ]; then
    echo -e "Skip WordPress installation: ${YELLOW}Yes${NC}"
fi

# Confirm before proceeding
echo
echo -e "${BLUE}Confirming settings...${NC}"
echo

cfg_confirm=$(get_yes_no "Proceed with these settings" "yes")
if [ "${cfg_confirm}" != "yes" ]; then
    log_error "Operation cancelled by user"
    exit 1
fi

# Main execution
echo
echo -e "${BLUE}Setting up ${arg_domain}...${NC}"
echo

# Purchase domain if not skipped
if [ "${arg_skip_domain}" != "true" ]; then
    if ! registrar_purchase_domain "${arg_domain}"; then
        exit 1
    fi
else
    log_warning "Skipping domain purchase"
fi

# Configure DNS if not skipped
if [ "${arg_skip_dns}" != "true" ]; then
    if ! registrar_configure_dns "${arg_domain}" "${cfg_server_ip}"; then
        exit 1
    fi
else
    log_warning "Skipping DNS configuration"
fi

# Create website if not skipped
if [ "${arg_skip_web}" != "true" ]; then
    if ! panel_create_website "${arg_domain}"; then
        exit 1
    fi
else
    log_warning "Skipping website creation"
fi

# Set up SSL if not skipped
if [ "${arg_skip_ssl}" != "true" ]; then
    if ! panel_setup_ssl "${arg_domain}"; then
        exit 1
    fi
else
    log_warning "Skipping SSL setup"
fi

# Create database if not skipped
if [ "${arg_skip_db}" != "true" ]; then
    if ! panel_create_database "${arg_domain}" "${cfg_db_pass}"; then
        exit 1
    fi
else
    log_warning "Skipping database creation"
fi

# Save credentials to file if requested
if [ "${arg_skip_db}" != "true" ]; then
    # cfg_save_creds=$(get_yes_no "Save credentials to file" "yes")
    # if [ "${cfg_save_creds}" = "yes" ]; then
    creds_file="${SCRIPT_DIR}/logs/${arg_domain}_$(date +%Y%m%d_%H%M%S).txt"
    {
        echo "[$(date +%Y-%m-%d_%H:%M:%S)]"
        echo "Website Setup Credentials for ${arg_domain}"
        echo "----------------------------------------"
        echo "Domain    : ${arg_domain}"
        echo "Registrar : ${arg_nameserver}"
        echo "Panel     : ${arg_panel}"
        echo "DB Name   : ${cfg_db_name}"
        echo "DB User   : ${cfg_db_user}"
        echo "DB Pass   : ${cfg_db_pass}"
        echo "----------------------------------------"
    } >"${creds_file}"
    chmod 600 "${creds_file}"
    echo
    echo -e "Credentials saved to ${GREEN}${creds_file}${NC}"
    echo -e "${YELLOW}Important: Please keep this file secure.${NC}"
    echo
    # fi
fi

# Extract source if not skipped
if [ "${arg_skip_wp}" == "true" ]; then
    log_warning "Skipping source extraction"
else
    extract_source "${source_file}" "${arg_domain}"
fi

# Complete
echo
echo -e "${GREEN}Website setup completed successfully!${NC}"
echo

exit 0

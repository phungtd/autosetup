#!/bin/bash

# sources.sh - Source URL handling and downloading
# This script provides functions to validate source URLs and download source files.

# Function to validate if URL points to an archive file
validate_source_url() {
    local url="$1"

    # Check if URL ends with supported archive extensions
    case "$url" in
    *.zip | *.tar.gz | *.tgz | *.tar | *.tar.bz2)
        return 0
        ;;
    *)
        return 1
        ;;
    esac
}

# Function to download source file
download_source() {
    local url="$1"
    local sources_dir="${SCRIPT_DIR}/sources"
    local filename

    # Create sources directory if it doesn't exist
    mkdir -p "$sources_dir"

    # Extract filename from URL
    filename=$(basename "$url")

    log_info "Downloading source file..."

    # Try wget first (more commonly available)
    if command -v wget >/dev/null 2>&1; then
        if wget --no-check-certificate -q "$url" -O "${sources_dir}/${filename}"; then
            log_success "Download successful"
            echo "${sources_dir}/${filename}"
            return 0
        fi
    fi

    # Fallback to curl if wget fails or not available
    if command -v curl >/dev/null 2>&1; then
        if curl -k -sSL "$url" -o "${sources_dir}/${filename}"; then
            log_success "Download successful"
            echo "${sources_dir}/${filename}"
            return 0
        fi
    fi

    # If both fail
    log_error "  Failed to download source file"
    return 1
}

# Function to get source URL
get_source_url() {
    local source="$1"
    local url=""
    local choice
    local options=()
    local var_name
    local var_value

    # If source is a URL, validate and return it
    if [[ "$source" =~ ^https?:// ]]; then
        if ! validate_source_url "$source"; then
            log_error "Invalid archive URL"
            return 1
        fi
        echo "$source"
        return 0
    fi

    # If source is provided, check if corresponding variable exists
    if [ -n "$source" ]; then
        var_name="cfg_sources_${source}"
        var_value="${!var_name}"
        if [ -n "$var_value" ] && validate_source_url "$var_value"; then
            echo "$var_value"
            return 0
        fi
    fi

    # Get all source variables
    while IFS='=' read -r var_name var_value; do
        # Trim whitespace using xargs
        var_name=$(echo "$var_name" | xargs)
        var_value=$(echo "$var_value" | xargs)

        if [[ "$var_name" =~ ^cfg_sources_ ]] && validate_source_url "$var_value"; then
            # Extract source name from variable name and trim
            source_name=$(echo "${var_name#cfg_sources_}" | xargs)
            options+=("$source_name" "$var_value")
        fi
    done < <(set | grep '^cfg_sources_')

    # If we get here, source wasn't found or wasn't provided
    echo -e "\nAvailable sources:\n" >&2
    for ((i = 0; i < ${#options[@]}; i += 2)); do
        echo "$((i / 2 + 1)). ${options[i]} -> ${options[i + 1]}" >&2
    done
    echo "$((${#options[@]} / 2 + 1)). Enter custom URL" >&2

    # Get user choice
    while true; do
        choice=$(get_input "Select source (1-$((${#options[@]} / 2 + 1)))" "")

        # Check if choice is a number and in range
        if [[ "$choice" =~ ^[0-9]+$ ]]; then
            if [ "$choice" -ge 1 ] && [ "$choice" -le "$((${#options[@]} / 2 + 1))" ]; then
                # If last option, get custom URL
                if [ "$choice" -eq "$((${#options[@]} / 2 + 1))" ]; then
                    while true; do
                        url=$(get_input "Enter custom source URL" "")
                        if [ -z "$url" ] || ! validate_source_url "$url"; then
                            echo -e "${RED}Invalid archive URL${NC}" >&2
                            continue
                        fi
                        break
                    done
                else
                    # Get URL from options
                    url="${options[($choice - 1) * 2 + 1]}"
                fi
                break
            fi
        fi
        echo -e "${RED}Invalid selection${NC}" >&2
    done

    echo "$url"
    return 0
}

# Function to extract source archive to domain's public_html
extract_source() {
    local source_file="$1"
    local domain="$2"
    local public_html="/home/${domain}/public_html"
    local backup_dir
    local current_owner
    local current_group

    # Check if source file exists
    if [ ! -f "$source_file" ]; then
        log_error "Source file not found: $source_file"
        return 1
    fi

    # Check if public_html exists
    if [ ! -d "$public_html" ]; then
        log_error "Public HTML directory not found: $public_html"
        return 1
    fi

    # Get current ownership
    current_owner=$(stat -c '%U' "$public_html")
    current_group=$(stat -c '%G' "$public_html")

    # Backup existing files if any exist
    if [ -n "$(ls -A "$public_html")" ]; then
        backup_dir="${public_html}_bak_$(date +%Y%m%d_%H%M%S)"
        log_info "Backing up existing files to: $backup_dir"
        if ! mv "$public_html" "$backup_dir"; then
            log_error "Failed to create backup"
            return 1
        fi
        mkdir -p "$public_html"
        # Restore original ownership
        chown "$current_owner:$current_group" "$public_html"
    fi

    # Create temp directory for extraction
    local temp_dir
    temp_dir=$(mktemp -d)

    log_info "Extracting source files..."

    # Extract based on file extension
    case "$source_file" in
    *.zip)
        if ! unzip -q "$source_file" -d "$temp_dir"; then
            log_error "Failed to extract ZIP file"
            rm -rf "$temp_dir"
            return 1
        fi
        ;;
    *.tar.gz | *.tgz)
        if ! tar -xzf "$source_file" -C "$temp_dir"; then
            log_error "Failed to extract TAR.GZ file"
            rm -rf "$temp_dir"
            return 1
        fi
        ;;
    *.tar)
        if ! tar -xf "$source_file" -C "$temp_dir"; then
            log_error "Failed to extract TAR file"
            rm -rf "$temp_dir"
            return 1
        fi
        ;;
    *.tar.bz2)
        if ! tar -xjf "$source_file" -C "$temp_dir"; then
            log_error "Failed to extract TAR.BZ2 file"
            rm -rf "$temp_dir"
            return 1
        fi
        ;;
    *)
        log_error "Unsupported archive format"
        rm -rf "$temp_dir"
        return 1
        ;;
    esac

    # Find the root directory of extracted files
    local source_root

    # If there's only one directory in temp_dir and it contains files, that's our root
    if [ "$(find "$temp_dir" -maxdepth 1 -type d | wc -l)" -eq 2 ]; then
        source_root=$(find "$temp_dir" -maxdepth 1 -type d -not -path "$temp_dir")
    else
        source_root="$temp_dir"
    fi

    # Move files to public_html
    log_info "Moving files to public_html..."
    if ! mv "$source_root"/* "$public_html/"; then
        log_error "Failed to move files to public_html"
        rm -rf "$temp_dir"
        return 1
    fi

    # Set proper permissions
    log_info "Setting permissions..."
    chown -R "$current_owner:$current_group" "$public_html"
    chmod -R 750 "$public_html"
    find "$public_html" -type f -exec chmod 640 {} \;

    # Cleanup
    rm -rf "$temp_dir"

    log_success "Source files extracted and validated successfully"

    # Find installer.php file
    local installer_file
    installer_file=$(find "$public_html" -maxdepth 1 -type f -name "*installer.php" | head -n1)
    if [ -z "$installer_file" ]; then
        log_error "Installer file not found"
    else
        log_info "Installer URL: https://${domain}/${installer_file##*/}"
    fi

    return 0
}

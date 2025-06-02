#!/bin/bash

# namecheap.sh - Namecheap API Implementation
# This script provides functions to interact with Namecheap using the API.

# Configuration variables
NAMECHEAP_API_KEY="${cfg_namecheap_api_key:-}"
NAMECHEAP_USERNAME="${cfg_namecheap_api_user:-}"
NAMECHEAP_API_URL="${cfg_namecheap_api_endpoint:-https://api.namecheap.com/xml.response}"
NAMECHEAP_CLIENT_IP="${cfg_server_ip:-$(get_server_ip)}" # Auto-detect server IP

# Contact information from config
NAMECHEAP_REGISTRANT_FNAME="${cfg_namecheap_registrant_fname:-}"
NAMECHEAP_REGISTRANT_LNAME="${cfg_namecheap_registrant_lname:-}"
NAMECHEAP_REGISTRANT_ADDR1="${cfg_namecheap_registrant_addr1:-}"
NAMECHEAP_REGISTRANT_CITY="${cfg_namecheap_registrant_city:-}"
NAMECHEAP_REGISTRANT_STATE="${cfg_namecheap_registrant_state:-}"
NAMECHEAP_REGISTRANT_POSTAL="${cfg_namecheap_registrant_postal:-}"
NAMECHEAP_REGISTRANT_COUNTRY="${cfg_namecheap_registrant_country:-}"
NAMECHEAP_REGISTRANT_PHONE="${cfg_namecheap_registrant_phone:-}"
NAMECHEAP_REGISTRANT_EMAIL="${cfg_namecheap_registrant_email:-${cfg_defaults_email:-}}"

# Check if API credentials are available
if [ -z "$NAMECHEAP_API_KEY" ] || [ -z "$NAMECHEAP_USERNAME" ]; then
    log_warning "Namecheap API credentials are not set in the config file. Please enter them below."

    # Prompt for credentials
    NAMECHEAP_USERNAME=$(get_input "Namecheap API User" "$NAMECHEAP_USERNAME")
    NAMECHEAP_API_KEY=$(get_input "Namecheap API Key" "$NAMECHEAP_API_KEY")

    if [ -z "$NAMECHEAP_API_KEY" ] || [ -z "$NAMECHEAP_USERNAME" ]; then
        log_error "Both Namecheap API Key and Username are required"
        exit 1
    fi
fi

# Function to make Namecheap API calls and log responses
namecheap_api_call() {
    # Input parameters
    local command="${1}"
    local params="${2}"

    # API parameters
    local api_params="ApiUser=$(url_encode "${NAMECHEAP_USERNAME}")&ApiKey=$(url_encode "${NAMECHEAP_API_KEY}")&UserName=$(url_encode "${NAMECHEAP_USERNAME}")"
    api_params+="&Command=$(url_encode "${command}")&ClientIp=$(url_encode "${NAMECHEAP_CLIENT_IP}")"

    # Response variables
    local response
    local exit_code

    log_info "Making Namecheap API call: ${command}"

    # Check if command is provided
    if [ -z "$command" ]; then
        log_error "Command is required"
        return 1
    fi

    # Add additional parameters if provided
    if [ -n "${params}" ]; then
        api_params+="&${params}"
    fi

    # Make API request
    response=$(make_request "${NAMECHEAP_API_URL}?${api_params}" "GET")
    exit_code=$?

    if [ $exit_code -ne 0 ]; then
        log_error "API request failed"
        return 1
    fi

    # Log the response
    if [ -n "${response}" ]; then
        log_debug "Response: ${response}"
    fi

    # Return the response and preserve exit code
    echo "${response}"
    return ${exit_code}
}

# Function to parse Namecheap XML error response
namecheap_parse_error() {
    # Input parameters
    local xml_response="${1}"

    # Error tracking variables
    local errors=""
    local found_error=0
    local error_number
    local error_message
    local line

    # Check if XML response is provided
    if [ -z "$xml_response" ]; then
        log_error "XML response is required"
        return 1
    fi

    # First check if response has OK status
    # if ! echo "$xml_response" | grep -q 'ApiResponse.*Status="OK"'; then
    #     echo "API response status is not OK"
    #     return 1
    # fi

    # Check if response contains errors section
    if echo "${xml_response}" | grep -q '<Errors>'; then
        # Use awk to properly parse XML and extract unique errors
        while IFS= read -r line; do
            if [[ ${line} =~ \<Error\ Number=\"([0-9]+)\"\>([^\<]+) ]]; then
                error_number="${BASH_REMATCH[1]}"
                error_message="${BASH_REMATCH[2]}"
                if [ -n "${errors}" ]; then
                    errors+="; " # Add separator between multiple errors
                fi
                errors+="Error ${error_number}: ${error_message}"
                found_error=1
            fi
        done < <(echo "${xml_response}" | grep -o '<Error Number="[0-9]*">[^<]*' | sort -u)
    fi

    if [ ${found_error} -eq 1 ]; then
        echo "${errors}"
        return 1
    fi
    return 0
}

# Function to check domain availability
namecheap_check_availability() {
    # Input parameters
    local domain="$1"

    # Response variables
    local response
    local error_msg

    log_info "Checking availability of domain: $domain"

    # Check if domain name is provided
    if [ -z "$domain" ]; then
        log_error "Domain name is required"
        return 1
    fi

    # Make API call
    response=$(namecheap_api_call "namecheap.domains.check" "DomainList=$domain")

    # Check for API errors first
    if ! error_msg=$(namecheap_parse_error "$response"); then
        log_error "Namecheap API error: $error_msg"
        return 2
    fi

    # Parse response for domain availability
    if echo "$response" | grep -q "Domain=\"$domain\" Available=\"true\""; then
        log_success "Domain $domain is available"
        return 0
    elif echo "$response" | grep -q "Domain=\"$domain\" Available=\"false\""; then
        log_error "Domain $domain is not available"
        return 1
    else
        log_error "Unexpected response format"
        return 2
    fi
}

# Function to get detailed information about a domain
namecheap_get_domain_info() {
    # Input parameters
    local domain="$1"

    # Response variables
    local response
    local error_msg
    local domain_block
    local result_line
    local result_status

    # Domain information variables
    local domain_id
    local owner_name
    local is_owner
    local is_premium
    local domain_details
    local created_date
    local expired_date

    # WhoisGuard variables
    local whoisguard_section
    local whoisguard_enabled
    local whoisguard_id
    local whoisguard_expiry

    # DNS variables
    local dns_provider
    local mod_rights

    log_info "Getting detailed information for domain: $domain"

    if [ -z "$domain" ]; then
        log_error "Domain name is required"
        return 1
    fi

    # Make API call
    response=$(namecheap_api_call "namecheap.domains.getInfo" "DomainName=$domain")

    # Check for API errors
    if ! error_msg=$(namecheap_parse_error "$response"); then
        log_error "Failed to get domain info: $error_msg"
        return 1
    fi

    # Extract the full domain block
    domain_block=$(echo "$response" | sed -n "/<DomainGetInfoResult[^>]*DomainName=\"$domain\"/,/<\/DomainGetInfoResult>/p")
    if [ -z "$domain_block" ]; then
        log_error "Failed to find domain info in response"
        return 1
    fi

    # Extract the opening tag line to get attributes
    result_line=$(echo "$domain_block" | head -n1)

    # Extract basic domain information from the result line
    result_status=$(echo "$result_line" | grep -oP 'Status="\K[^"]*')
    if [ "$result_status" != "Ok" ]; then
        log_error "Failed to get domain info: Result status is $result_status"
        return 1
    fi

    domain_id=$(echo "$result_line" | grep -oP 'ID="\K[^"]*')
    owner_name=$(echo "$result_line" | grep -oP 'OwnerName="\K[^"]*')
    is_owner=$(echo "$result_line" | grep -oP 'IsOwner="\K[^"]*')
    is_premium=$(echo "$result_line" | grep -oP 'IsPremium="\K[^"]*')

    # Extract dates from DomainDetails section
    domain_details=$(echo "$domain_block" | sed -n '/<DomainDetails/,/<\/DomainDetails>/p')
    created_date=$(echo "$domain_details" | grep -oP '(?<=<CreatedDate>)[^<]*')
    expired_date=$(echo "$domain_details" | grep -oP '(?<=<ExpiredDate>)[^<]*')

    # Extract WhoisGuard information
    whoisguard_section=$(echo "$domain_block" | sed -n '/<Whoisguard/,/<\/Whoisguard>/p')
    whoisguard_enabled=$(echo "$whoisguard_section" | grep -oP 'Enabled="\K[^"]*')
    if [ "$whoisguard_enabled" == "True" ]; then
        whoisguard_id=$(echo "$whoisguard_section" | grep -oP '(?<=<ID>)[^<]*')
        whoisguard_expiry=$(echo "$whoisguard_section" | grep -oP '(?<=<ExpiredDate>)[^<]*')
    fi

    # Extract DNS provider information
    dns_provider=$(echo "$domain_block" | grep -oP '(?<=<DnsDetails ProviderType=")[^"]*')
    mod_rights=$(echo "$domain_block" | grep -oP '(?<=<Modificationrights All=")[^"]*')

    # Display the information
    echo -e "${GREEN}Domain Information for $domain:${NC}"
    echo "Basic Information:"
    echo "  Domain ID: $domain_id"
    echo "  Owner: $owner_name"
    echo "  Is Owner: $is_owner"
    echo "  Is Premium: $is_premium"
    echo
    echo "Dates:"
    echo "  Created: $created_date"
    echo "  Expires: $expired_date"
    echo
    echo "WhoisGuard:"
    echo "  Enabled: $whoisguard_enabled"
    if [ "$whoisguard_enabled" == "True" ]; then
        echo "  ID: $whoisguard_id"
        echo "  Expires: $whoisguard_expiry"
    fi
    echo
    echo "DNS Provider: $dns_provider"
    echo "Modification Rights: $mod_rights"

    return 0
}

# Function to check if a domain is owned by the current user
namecheap_is_domain_owned() {
    local domain="$1"

    local response error_msg domain_block result_line is_owner

    log_info "Checking ownership of domain: $domain"

    # Check if domain name is provided
    if [ -z "$domain" ]; then
        log_error "Domain name is required"
        return 2
    fi

    # Make API call
    response=$(namecheap_api_call "namecheap.domains.getInfo" "DomainName=$domain")

    # Check for API errors
    if ! error_msg=$(namecheap_parse_error "$response"); then
        log_error "Failed to check domain ownership: $error_msg"
        return 2
    fi

    # Extract the domain block
    domain_block=$(echo "$response" | sed -n "/<DomainGetInfoResult[^>]*DomainName=\"$domain\"/,/<\/DomainGetInfoResult>/p")
    if [ -z "$domain_block" ]; then
        log_error "Failed to find domain info in response"
        return 2
    fi

    # Extract the opening tag line to get attributes
    result_line=$(echo "$domain_block" | head -n1)

    # Extract IsOwner attribute
    is_owner=$(echo "$result_line" | grep -oP 'IsOwner="\K[^"]*')

    if [ "$is_owner" == "true" ]; then
        log_success "Domain $domain is owned by the current user"
        return 0
    else
        log_info "Domain $domain is not owned by the current user"
        return 1
    fi
}

# Function to get list of saved addresses
namecheap_get_address_list() {
    # Response variables
    local response
    local error_msg
    local addresses=""
    local id
    local name
    local line

    log_info "Fetching saved addresses from Namecheap"

    # Get list of addresses
    response=$(namecheap_api_call "namecheap.users.address.getList" "")

    # Check for API errors first
    if ! error_msg=$(namecheap_parse_error "$response"); then
        log_error "Failed to fetch address list: $error_msg"
        return 1
    fi

    # Parse the response and extract address IDs and names
    while IFS= read -r line; do
        if [[ $line =~ List\ AddressId=\"([0-9]+)\"\ AddressName=\"([^\"]+)\" ]]; then
            id="${BASH_REMATCH[1]}"
            name="${BASH_REMATCH[2]}"
            if [ -n "$addresses" ]; then
                addresses+="\n"
            fi
            addresses+="$id|$name"
        fi
    done < <(echo "$response" | grep -o '<List AddressId="[0-9]*" AddressName="[^"]*"')

    echo -e "$addresses"
    return 0
}

# Function to get address details by ID
namecheap_get_address_info() {
    # Input parameters
    local address_id="$1"

    # Response variables
    local response
    local error_msg
    local fname lname addr1 addr2 city state postal country phone email org name

    log_info "Fetching address details for ID: $address_id"

    # Check if address ID is provided
    if [ -z "$address_id" ]; then
        log_error "Address ID is required"
        return 1
    fi

    # Get address details
    response=$(namecheap_api_call "namecheap.users.address.getInfo" "AddressId=$address_id")

    # Check for API errors first
    if ! error_msg=$(namecheap_parse_error "$response"); then
        log_error "Failed to fetch address details: $error_msg"
        return 1
    fi

    # Parse the response and extract address details
    fname=$(echo "$response" | grep -oP '(?<=<FirstName>)[^<]+')
    lname=$(echo "$response" | grep -oP '(?<=<LastName>)[^<]+')
    addr1=$(echo "$response" | grep -oP '(?<=<Address1>)[^<]+')
    addr2=$(echo "$response" | grep -oP '(?<=<Address2>)[^<]+')
    city=$(echo "$response" | grep -oP '(?<=<City>)[^<]+')
    state=$(echo "$response" | grep -oP '(?<=<StateProvince>)[^<]+')
    postal=$(echo "$response" | grep -oP '(?<=<Zip>)[^<]+')
    country=$(echo "$response" | grep -oP '(?<=<Country>)[^<]+')
    phone=$(echo "$response" | grep -oP '(?<=<Phone>)[^<]+')
    email=$(echo "$response" | grep -oP '(?<=<EmailAddress>)[^<]+')
    org=$(echo "$response" | grep -oP '(?<=<Organization>)[^<]+')
    name=$(echo "$response" | grep -oP '(?<=<AddressName>)[^<]+')

    # Return the formatted address details
    echo "FNAME=$fname"
    echo "LNAME=$lname"
    echo "ADDR1=$addr1"
    echo "ADDR2=$addr2"
    echo "CITY=$city"
    echo "STATE=$state"
    echo "POSTAL=$postal"
    echo "COUNTRY=$country"
    echo "PHONE=$phone"
    echo "EMAIL=$email"
    echo "ORG=$org"
    echo "NAME=$name"

    return 0
}

# Function to select address for domain registration
namecheap_select_address() {
    # Display variables
    local display_output=""
    local show_config=1

    # Address storage
    declare -A address_cache
    local address_list
    local info

    # Selection variables
    local valid_ids=""
    local selection=""
    local valid_selection=0

    # Return value
    local return_output=""

    # Address field variables
    local org="" fname="" lname="" addr1="" addr2="" city="" state="" postal="" country="" phone="" email=""
    local var_name field id name key value has_all_fields

    # Check if config address has all required fields
    for field in FNAME LNAME ADDR1 CITY STATE POSTAL COUNTRY PHONE EMAIL; do
        var_name="NAMECHEAP_REGISTRANT_$field"
        if [ -z "${!var_name}" ]; then
            log_info "Config address is incomplete - missing required field: $field"
            show_config=0
            break
        fi
    done

    # First show the config option if valid
    display_output+="\nAvailable Addresses:\n"
    if [ $show_config -eq 1 ]; then
        display_output+="\n[${GREEN}-1${NC}] Address from config.ini:\n"
        display_output+="    Name: ${NAMECHEAP_REGISTRANT_FNAME} ${NAMECHEAP_REGISTRANT_LNAME}\n"
        display_output+="    Address: ${NAMECHEAP_REGISTRANT_ADDR1}\n"
        display_output+="    Location: ${NAMECHEAP_REGISTRANT_CITY}, ${NAMECHEAP_REGISTRANT_STATE} ${NAMECHEAP_REGISTRANT_POSTAL}\n"
        display_output+="    Country: ${NAMECHEAP_REGISTRANT_COUNTRY}\n"
        display_output+="    Phone: ${NAMECHEAP_REGISTRANT_PHONE}\n"
        display_output+="    Email: ${NAMECHEAP_REGISTRANT_EMAIL}\n"

        # Store config address in cache
        address_cache[-1]="FNAME=${NAMECHEAP_REGISTRANT_FNAME}\n"
        address_cache[-1]+="LNAME=${NAMECHEAP_REGISTRANT_LNAME}\n"
        address_cache[-1]+="ADDR1=${NAMECHEAP_REGISTRANT_ADDR1}\n"
        address_cache[-1]+="CITY=${NAMECHEAP_REGISTRANT_CITY}\n"
        address_cache[-1]+="STATE=${NAMECHEAP_REGISTRANT_STATE}\n"
        address_cache[-1]+="POSTAL=${NAMECHEAP_REGISTRANT_POSTAL}\n"
        address_cache[-1]+="COUNTRY=${NAMECHEAP_REGISTRANT_COUNTRY}\n"
        address_cache[-1]+="PHONE=${NAMECHEAP_REGISTRANT_PHONE}\n"
        address_cache[-1]+="EMAIL=${NAMECHEAP_REGISTRANT_EMAIL}"
    fi

    # Track valid selection IDs
    [ $show_config -eq 1 ] && valid_ids="-1" # Add config ID if valid

    # Get saved addresses from Namecheap
    if address_list=$(namecheap_get_address_list); then
        # Display each address
        while IFS='|' read -r id name; do
            if info=$(namecheap_get_address_info "$id"); then
                # Reset field variables for each iteration
                org="" fname="" lname="" addr1="" addr2="" city="" state="" postal="" country="" phone="" email=""
                has_all_fields=1

                while IFS='=' read -r key value; do
                    case "$key" in
                    "FNAME") fname="$value" ;;
                    "LNAME") lname="$value" ;;
                    "ADDR1") addr1="$value" ;;
                    "CITY") city="$value" ;;
                    "STATE") state="$value" ;;
                    "POSTAL") postal="$value" ;;
                    "COUNTRY") country="$value" ;;
                    "PHONE") phone="$value" ;;
                    "EMAIL") email="$value" ;;
                    esac
                done <<<"$info"

                # Set email to default if not provided
                email="${email:-${cfg_defaults_email:-}}"

                # Verify all required fields are non-empty
                for var in fname lname addr1 city state postal country phone email; do
                    if [ -z "${!var}" ]; then
                        log_info "Address is incomplete - missing required field: $var"
                        has_all_fields=0
                        break
                    fi
                done

                if [ $has_all_fields -eq 1 ]; then
                    # Store address info in cache
                    address_cache["${id}"]="$info"

                    # Add to valid IDs list
                    [ -n "${valid_ids}" ] && valid_ids+=" "
                    valid_ids+="$id"

                    display_output+="\n[${GREEN}$id${NC}] Address from Namecheap:\n"
                    display_output+="    Name: $fname $lname\n"
                    display_output+="    Address: $addr1\n"
                    display_output+="    Location: $city, $state $postal\n"
                    display_output+="    Country: $country\n"
                    display_output+="    Phone: $phone\n"
                    display_output+="    Email: $email\n"
                fi
            fi
        done <<<"$address_list"
    fi

    # Check if we have any valid addresses
    if [ -z "${valid_ids}" ]; then
        log_error "No valid addresses found with all required fields"
        return 1
    fi

    # Remove trailing newline and display
    echo -e "${display_output%$'\n'}" >&2

    # Prompt for selection
    while [ $valid_selection -eq 0 ]; do
        selection=$(get_input "Select address ID" "")

        # Validate input is a number
        # if ! [[ "$selection" =~ ^-?[0-9]+$ ]]; then
        #     echo -e "${RED}Please enter a number.${NC}" >&2
        #     continue
        # fi

        # Check if selection is in valid_ids
        if [[ " ${valid_ids} " =~ [[:space:]]${selection}[[:space:]] ]]; then
            valid_selection=1
        else
            echo -e "${RED}Invalid selection${NC}" >&2
        fi
    done

    # Return the cached address info
    return_output="${address_cache[${selection}]}"

    # Output the final result
    echo -e "$return_output"
    return 0
}

# Function to purchase domain
registrar_purchase_domain() {
    # Input parameters
    local domain="$1"

    # Address information variables
    local address_info
    local fname lname addr1 city state postal country phone email

    # API variables
    local params
    local response
    local error_msg
    local domain_pattern
    local result_line
    local domain_id
    local order_id
    local amount
    local registered

    log_info "Purchasing domain: $domain"

    # Check if domain name is provided
    if [ -z "$domain" ]; then
        log_error "Domain name is required"
        return 1
    fi

    # Check if domain is already owned by the current user
    if namecheap_is_domain_owned "$domain"; then
        return 0
    fi

    # Check if domain is available first
    if ! namecheap_check_availability "$domain"; then
        return 1
    fi

    # Get address information
    if ! address_info=$(namecheap_select_address); then
        return 1
    fi

    # Parse address information into variables
    while IFS='=' read -r key value; do
        case "$key" in
        "FNAME") fname="$value" ;;
        "LNAME") lname="$value" ;;
        "ADDR1") addr1="$value" ;;
        "CITY") city="$value" ;;
        "STATE") state="$value" ;;
        "POSTAL") postal="$value" ;;
        "COUNTRY") country="$value" ;;
        "PHONE") phone="$value" ;;
        "EMAIL") email="$value" ;;
        esac
    done <<<"$address_info"

    # Build API parameters for domain registration with required fields only
    params="DomainName=$(url_encode "$domain")&Years=1"

    # Registrant Information
    params+="&RegistrantFirstName=$(url_encode "$fname")"
    params+="&RegistrantLastName=$(url_encode "$lname")"
    params+="&RegistrantAddress1=$(url_encode "$addr1")"
    params+="&RegistrantCity=$(url_encode "$city")"
    params+="&RegistrantStateProvince=$(url_encode "$state")"
    params+="&RegistrantPostalCode=$(url_encode "$postal")"
    params+="&RegistrantCountry=$(url_encode "$country")"
    params+="&RegistrantPhone=$(url_encode "$phone")"
    params+="&RegistrantEmailAddress=$(url_encode "$email")"

    # Tech Contact (same as Registrant)
    params+="&TechFirstName=$(url_encode "$fname")"
    params+="&TechLastName=$(url_encode "$lname")"
    params+="&TechAddress1=$(url_encode "$addr1")"
    params+="&TechCity=$(url_encode "$city")"
    params+="&TechStateProvince=$(url_encode "$state")"
    params+="&TechPostalCode=$(url_encode "$postal")"
    params+="&TechCountry=$(url_encode "$country")"
    params+="&TechPhone=$(url_encode "$phone")"
    params+="&TechEmailAddress=$(url_encode "$email")"

    # Admin Contact (same as Registrant)
    params+="&AdminFirstName=$(url_encode "$fname")"
    params+="&AdminLastName=$(url_encode "$lname")"
    params+="&AdminAddress1=$(url_encode "$addr1")"
    params+="&AdminCity=$(url_encode "$city")"
    params+="&AdminStateProvince=$(url_encode "$state")"
    params+="&AdminPostalCode=$(url_encode "$postal")"
    params+="&AdminCountry=$(url_encode "$country")"
    params+="&AdminPhone=$(url_encode "$phone")"
    params+="&AdminEmailAddress=$(url_encode "$email")"

    # AuxBilling Contact (same as Registrant)
    params+="&AuxBillingFirstName=$(url_encode "$fname")"
    params+="&AuxBillingLastName=$(url_encode "$lname")"
    params+="&AuxBillingAddress1=$(url_encode "$addr1")"
    params+="&AuxBillingCity=$(url_encode "$city")"
    params+="&AuxBillingStateProvince=$(url_encode "$state")"
    params+="&AuxBillingPostalCode=$(url_encode "$postal")"
    params+="&AuxBillingCountry=$(url_encode "$country")"
    params+="&AuxBillingPhone=$(url_encode "$phone")"
    params+="&AuxBillingEmailAddress=$(url_encode "$email")"

    # Make API call
    response=$(namecheap_api_call "namecheap.domains.create" "$params")

    # Check for API errors first
    if ! error_msg=$(namecheap_parse_error "$response"); then
        log_error "Failed to purchase domain: $error_msg"
        return 1
    fi

    # Find the DomainCreateResult for our domain and extract details
    domain_pattern="<DomainCreateResult[^>]*Domain=\"$domain\"[^>]*>"
    if ! echo "$response" | grep -q "$domain_pattern"; then
        log_error "Domain $domain not found in registration response"
        return 1
    fi

    # Extract registration details from the matching DomainCreateResult
    result_line=$(echo "$response" | grep "$domain_pattern")
    domain_id=$(echo "$result_line" | grep -oP 'DomainID="\K[^"]*')
    order_id=$(echo "$result_line" | grep -oP 'OrderID="\K[^"]*')
    amount=$(echo "$result_line" | grep -oP 'ChargedAmount="\K[^"]*')
    registered=$(echo "$result_line" | grep -oP 'Registered="\K[^"]*')

    if [ "$registered" == "true" ]; then
        log_success "Domain $domain purchased successfully Domain ID: $domain_id, Order ID: $order_id, Amount: \$$amount"
        return 0
    else
        log_error "Domain registration response indicated failure"
        return 1
    fi
}

# Function to configure DNS
registrar_configure_dns() {
    # Input parameters
    local domain="$1"
    local server_ip="$2"

    # Domain parts
    local sld=$(echo "$domain" | cut -d. -f1)
    local tld=$(echo "$domain" | cut -d. -f2-)

    # API variables
    local params
    local response
    local error_msg
    local result
    local response_domain
    local is_success

    log_info "Configuring DNS for domain: $domain to point to IP: $server_ip"

    # Check if domain name and server IP are provided
    if [ -z "$domain" ] || [ -z "$server_ip" ]; then
        log_error "Domain name and server IP are required"
        return 1
    fi

    # Set default DNS
    params="SLD=$sld&TLD=$tld"
    response=$(namecheap_api_call "namecheap.domains.dns.setDefault" "$params")

    # Check for API errors first
    if ! error_msg=$(namecheap_parse_error "$response"); then
        log_error "Failed to set default DNS: $error_msg"
        return 1
    fi

    # Set DNS records
    params="SLD=$sld&TLD=$tld"
    params+="&HostName1=@&RecordType1=A&Address1=$server_ip&TTL1=1800"
    params+="&HostName2=www&RecordType2=CNAME&Address2=$domain&TTL2=1800"
    response=$(namecheap_api_call "namecheap.domains.dns.setHosts" "$params")

    # Check for API errors first
    if ! error_msg=$(namecheap_parse_error "$response"); then
        log_error "Failed to configure DNS hosts: $error_msg"
        return 1
    fi

    # Extract and validate the DomainDNSSetHostsResult element
    result=$(echo "$response" | grep -oP "<DomainDNSSetHostsResult[^>]*>")
    if [ -z "$result" ]; then
        log_error "Failed to find DomainDNSSetHostsResult in response"
        return 1
    fi

    # Check if it's for the correct domain
    response_domain=$(echo "$result" | grep -oP 'Domain="\K[^"]*')
    if [ "$response_domain" != "$domain" ]; then
        log_error "Response domain '$response_domain' does not match requested domain '$domain'"
        return 1
    fi

    # Check if operation was successful
    is_success=$(echo "$result" | grep -oP 'IsSuccess="\K[^"]*')
    if [ "$is_success" != "true" ]; then
        log_error "DNS host update was not successful"
        return 1
    fi

    log_success "DNS records set successfully for $domain"

    return 0
}

log_info "Namecheap API module loaded"

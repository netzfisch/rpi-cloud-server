#!/bin/bash
# ========================================================================
# generate-userdata.sh - Cloud-init User-Data Generator
# ========================================================================
#
# This script validates secrets.env and generates user-data by substituting
# variables from secrets.env into user-data.template using envsubst.
#
# Usage: ./generate-userdata.sh
# ========================================================================

set -e  # Exit immediately if a command exits with a non-zero status
set -u  # Treat unset variables as an error

# ========================================================================
# Color Output Functions
# ========================================================================

# Generic colored message output (reusable for all message types)
# Args: $1=message, $2=color_code (1=red, 2=green, 3=yellow), $3=optional_suffix
msg() { 
    echo -e "\033[0;3${2}m${1}\033[0m${3:-}"
}

# Wrapper functions for semantic clarity and convenience
err()  { msg "✗ Error: $1" 1 " " >&2; exit 1; }  # Red, exit on error
ok()   { msg "✓ $1" 2; }                          # Green
warn() { msg "⚠ Warning: $1" 3; }                 # Yellow
info() { echo "ℹ $1"; }                           # No color

# ========================================================================
# Configuration
# ========================================================================

SECRETS="secrets.env"
TEMPLATE="user-data.template"
OUTPUT="user-data"
EXAMPLE="secrets.env.example"

# List of all required variables that must be defined in secrets.env
REQUIRED_VARS=(
    HOSTNAME
    GITHUB_USER
    USER1
    USER1_SAMBA_PASSWORD
    USER2
    USER2_SAMBA_PASSWORD
    STATIC_IP
    GATEWAY_IP
    DNS_SERVERS
    VLAN_PRIVAT
    PRIVAT_SUBNET_OCTET
    VLAN_IOT
    IOT_DHCP_START
    IOT_DHCP_END
    VLAN_GUEST
    GUEST_DHCP_START
    GUEST_DHCP_END
    UPSTREAM_DNS_SERVER
    DOMAIN
    DDNS_HOSTNAME
    DDNS_TOKEN
)

# ========================================================================
# Validation Functions
# ========================================================================

# Check if required files exist
check_files_exist() {
    [[ -f "$SECRETS" ]] || err "$SECRETS not found!\n\n  1. cp $EXAMPLE $SECRETS\n  2. Edit $SECRETS and replace placeholders"
    [[ -f "$TEMPLATE" ]] || err "Template $TEMPLATE not found!"
}

# Validate that all required variables are set and check for placeholders
validate_variables() {
    local missing_vars=()
    local placeholder_vars=()

    # Check each required variable
    for var in "${REQUIRED_VARS[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            # Variable is not set or empty
            missing_vars+=("$var")
        elif [[ "${!var}" == CHANGE_ME* ]]; then
            # Variable still has placeholder value
            placeholder_vars+=("$var=${!var}")
        fi
    done

    # Abort if any variables are missing
    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        err "Missing variables:\n$(printf '  - %s\n' "${missing_vars[@]}")"
    fi

    # Warn about placeholder values and ask for confirmation
    if [[ ${#placeholder_vars[@]} -gt 0 ]]; then
        warn "Found placeholder values:\n$(printf '  - %s\n' "${placeholder_vars[@]}")\n"
        read -p "Continue anyway? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            info "Aborted by user"
            exit 0
        fi
    fi
}

# Validate generated file with cloud-init schema
validate_cloud_init_schema() {
    command -v cloud-init &>/dev/null || return 0  # Skip if not installed

    info "Validating cloud-init schema..."

    # Capture full output including errors
    validation_output=$(cloud-init schema --config-file "$OUTPUT" 2>&1)
    
    if echo "$validation_output" | grep -q "Valid schema"; then
        ok "Cloud-init schema validation passed"
    else
        warn "Cloud-init schema validation failed:"
        echo "$validation_output"
        echo ""
        info "You may still proceed, but check the configuration carefully"
    fi
}

# ========================================================================
# Main Script
# ========================================================================

main() {
    # Step 1: Check that required files exist
    check_files_exist

    # Step 2: Load secrets from file
    info "Reading secrets from $SECRETS..."
    source "$SECRETS"

    # Step 3: Validate all required variables
    validate_variables

    # Step 4: Render template with variable substitution
    info "Rendering $TEMPLATE → $OUTPUT..."
    export "${REQUIRED_VARS[@]}"
    # Only substitute our variables, preserve cloud-init variables like $RELEASE and $UPTIME
    envsubst "$(printf '${%s} ' "${REQUIRED_VARS[@]}")" < "$TEMPLATE" > "$OUTPUT"
    ok "Successfully rendered $OUTPUT"

    # Step 5: Validate generated configuration
    validate_cloud_init_schema

    # Step 6: Show next steps to user
    echo ""
    ok "Done! Next steps:"
    echo "  1. Review the generated $OUTPUT"
    echo "  2. Copy to SD card boot partition:"
    echo "     cp $OUTPUT /media/\$USER/system-boot/user-data"
    echo ""
}

# Run main function
main

#!/bin/bash

# TrueNAS Scale App Update Script (Docker-based)
# This script updates all applications in TrueNAS Scale using the middleware API

# Configuration
TRUENAS_HOST="localhost"  # Change to your TrueNAS IP if running remotely
API_KEY=""  # Set your API key here or pass as environment variable

# Plex Configuration
PLEX_HOST=""  # Plex server IP (leave empty to auto-detect from TrueNAS)
PLEX_PORT="32400"  # Default Plex port
PLEX_TOKEN=""  # Plex authentication token
PLEX_CHECK_SESSIONS=true  # Set to false to skip Plex session checks

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to display usage
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  -h, --host HOST      TrueNAS host/IP (default: localhost)"
    echo "  -k, --api-key KEY    API key for authentication"
    echo "  -u, --username USER  Username for authentication (default: root)"
    echo "  -p, --password PASS  Password for authentication"
    echo "  -d, --dry-run        Show what would be updated without actually updating"
    echo "  -f, --force          Force update even if no updates appear available"
    echo "  -w, --wait           Wait for each update to complete before starting the next"
    echo "  -t, --plex-token     Plex authentication token for session checking"
    echo "  --plex-host HOST     Override Plex server IP"
    echo "  --plex-port PORT     Override Plex server port (default: 32400)"
    echo "  --skip-plex-check    Skip Plex session detection entirely"
    echo "  --help               Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --api-key your-api-key-here"
    echo "  $0 --username root --password yourpassword"
    echo "  $0 --host 192.168.1.100 --api-key your-key --dry-run"
    echo "  $0 --api-key your-key --plex-token your-plex-token --force"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--host)
            TRUENAS_HOST="$2"
            shift 2
            ;;
        -k|--api-key)
            API_KEY="$2"
            shift 2
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -f|--force)
            FORCE_UPDATE=true
            shift
            ;;
        -t|--plex-token)
            PLEX_TOKEN="$2"
            shift 2
            ;;
        --plex-host)
            PLEX_HOST="$2"
            shift 2
            ;;
        --plex-port)
            PLEX_PORT="$2"
            shift 2
            ;;
        --skip-plex-check)
            PLEX_CHECK_SESSIONS=false
            shift
            ;;
        -w|--wait)
            WAIT_FOR_COMPLETION=true
            shift
            ;;
        --help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Check if we have API key
if [[ -z "$API_KEY" ]]; then
    echo -e "${RED}Error: TrueNAS API key is required${NC}"
    echo "Set API_KEY environment variable or use --api-key option"
    echo ""
    echo "To create an API key:"
    echo "1. Log into TrueNAS Scale web interface"
    echo "2. Click the user icon → My API Keys"
    echo "3. Click Add to create a new key"
    echo "4. Copy the generated key and use it with this script"
    exit 1
fi

# Function to make API calls
api_call() {
    local method="$1"
    local endpoint="$2"
    local data="$3"
    
    local curl_opts=()
    curl_opts+=("-s" "-X" "$method")
    curl_opts+=("-H" "Content-Type: application/json")
    curl_opts+=("-H" "Authorization: Bearer $API_KEY")
    
    if [[ -n "$data" ]]; then
        curl_opts+=("-d" "$data")
    fi
    
    curl "${curl_opts[@]}" "http://$TRUENAS_HOST/api/v2.0/$endpoint"
}

# Function to check if jq is available
check_jq() {
    if ! command -v jq &> /dev/null; then
        echo -e "${RED}Error: jq is required but not installed${NC}"
        echo "Please install jq: apt-get install jq (Debian/Ubuntu) or yum install jq (RHEL/CentOS)"
        exit 1
    fi
}

# Function to test connection and authentication
test_connection() {
    echo -e "${BLUE}Testing connection to TrueNAS Scale...${NC}"
    
    local response=$(api_call "GET" "system/info" 2>/dev/null)
    
    if [[ $? -ne 0 ]] || [[ -z "$response" ]]; then
        echo -e "${RED}Error: Cannot connect to TrueNAS Scale at $TRUENAS_HOST${NC}"
        echo "Please check:"
        echo "  - Host/IP address is correct"
        echo "  - TrueNAS Scale is running and accessible"
        echo "  - Network connectivity"
        exit 1
    fi
    
    if echo "$response" | jq -e '.version' >/dev/null 2>&1; then
        local version=$(echo "$response" | jq -r '.version')
        echo -e "${GREEN}Connected to TrueNAS Scale version: $version${NC}"
    else
        echo -e "${RED}Error: Authentication failed${NC}"
        echo "Please check your API key"
        exit 1
    fi
}

# Function to get list of installed applications
get_apps() {
    echo -e "${BLUE}Fetching installed applications...${NC}"
    
    local response=$(api_call "GET" "app")
    
    if [[ $? -ne 0 ]] || [[ -z "$response" ]]; then
        echo -e "${RED}Error: Failed to fetch applications${NC}"
        exit 1
    fi
    
    echo "$response"
}

# Function to check app status
get_app_status() {
    local app_id="$1"
    
    local response=$(api_call "GET" "app/id/$app_id")
    
    if [[ $? -ne 0 ]] || [[ -z "$response" ]]; then
        return 1
    fi
    
    echo "$response"
}

# Function to update an application
update_app() {
    local app_id="$1"
    local app_name="$2"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${YELLOW}[DRY RUN] Would update: $app_name (ID: $app_id)${NC}"
        return 0
    fi
    
    echo -e "${BLUE}Updating $app_name (ID: $app_id)...${NC}"
    
    # Trigger app update
    local response=$(api_call "POST" "app/id/$app_id/upgrade" "{}")
    
    if [[ $? -ne 0 ]]; then
        echo -e "${RED}Failed to trigger update for $app_name${NC}"
        return 1
    fi
    
    # Check if the response indicates success
    if echo "$response" | jq -e '.error' >/dev/null 2>&1; then
        local error_msg=$(echo "$response" | jq -r '.error')
        echo -e "${RED}Update failed for $app_name: $error_msg${NC}"
        return 1
    fi
    
    echo -e "${GREEN}Update initiated for $app_name${NC}"
    
    # Wait for completion if requested
    if [[ "$WAIT_FOR_COMPLETION" == "true" ]]; then
        echo -e "${BLUE}Waiting for $app_name update to complete...${NC}"
        wait_for_app_ready "$app_id" "$app_name"
    fi
    
    return 0
}

# Function to get Plex server info and detect host
get_plex_info() {
    if [[ -n "$PLEX_HOST" ]]; then
        return 0
    fi
    
    # Try to auto-detect Plex from TrueNAS apps
    local apps_response=$(api_call "GET" "app" 2>/dev/null)
    
    if [[ $? -eq 0 ]] && [[ -n "$apps_response" ]]; then
        local plex_app=$(echo "$apps_response" | jq -r '.[] | select(.name == "plex" or .id | contains("plex")) | .id' 2>/dev/null | head -1)
        
        if [[ -n "$plex_app" ]]; then
            # Get app details to find the host
            local app_details=$(api_call "GET" "app/id/$plex_app" 2>/dev/null)
            
            if [[ $? -eq 0 ]] && [[ -n "$app_details" ]]; then
                # Try to extract IP from app config or use TrueNAS host
                PLEX_HOST="$TRUENAS_HOST"
                echo -e "${GREEN}Auto-detected Plex server at: $PLEX_HOST:$PLEX_PORT${NC}"
                return 0
            fi
        fi
    fi
    
    # Fallback to TrueNAS host
    PLEX_HOST="$TRUENAS_HOST"
    return 0
}

# Function to check Plex active sessions
check_plex_sessions() {
    if [[ "$PLEX_CHECK_SESSIONS" != "true" ]]; then
        return 0
    fi
    
    get_plex_info
    
    if [[ -z "$PLEX_TOKEN" ]]; then
        echo -e "${YELLOW}Warning: No Plex token provided. Cannot check active sessions.${NC}"
        echo "Use --plex-token option to provide your Plex authentication token"
        echo "Or use --skip-plex-check to skip this check"
        return 1
    fi
    
    echo -e "${BLUE}Checking Plex active sessions...${NC}"
    echo -e "${BLUE}Plex URL: http://$PLEX_HOST:$PLEX_PORT/status/sessions${NC}"
    
    local sessions_url="http://$PLEX_HOST:$PLEX_PORT/status/sessions?X-Plex-Token=$PLEX_TOKEN"
    local response=$(curl -s -H "Accept: application/json" "$sessions_url" 2>/dev/null)
    
    if [[ $? -ne 0 ]] || [[ -z "$response" ]]; then
        echo -e "${YELLOW}Warning: Could not connect to Plex server at $PLEX_HOST:$PLEX_PORT${NC}"
        echo "Make sure Plex is running and accessible"
        return 1
    fi
    
    # Debug: Show first 200 characters of Plex response
    echo -e "${BLUE}Plex Response (first 200 chars): ${NC}"
    echo "$response" | head -c 200
    echo ""
    
    # Parse JSON response to count active sessions
    local session_count=0
    
    if echo "$response" | jq . >/dev/null 2>&1; then
        # JSON response - use jq to parse
        session_count=$(echo "$response" | jq -r '.MediaContainer.size // 0' 2>/dev/null || echo "0")
    else
        # Fallback to XML parsing if JSON not available
        if echo "$response" | grep -q 'size="[1-9]' 2>/dev/null; then
            session_count=$(echo "$response" | grep -o 'size="[0-9]*"' | head -1 | cut -d'"' -f2)
        fi
    fi
    
    if [[ "$session_count" -gt 0 ]]; then
        echo -e "${RED}Warning: $session_count active Plex session(s) detected!${NC}"
        
        # Try to get more details about active sessions using JSON
        if echo "$response" | jq . >/dev/null 2>&1; then
            echo "Active sessions:"
            echo "$response" | jq -r '.MediaContainer.Metadata[]? | "  - User: \(.User?.title // "Unknown") | Title: \(.title // .grandparentTitle // "Unknown") | State: \(.Player?.state // "unknown")"' 2>/dev/null || true
        fi
        
        return 1
    else
        echo -e "${GREEN}No active Plex sessions detected${NC}"
        return 0
    fi
}
wait_for_app_ready() {
    local app_id="$1"
    local app_name="$2"
    local max_wait=600  # 10 minutes
    local wait_time=0
    
    while [[ $wait_time -lt $max_wait ]]; do
        local status_response=$(get_app_status "$app_id")
        
        if [[ $? -eq 0 ]]; then
            local state=$(echo "$status_response" | jq -r '.state // "unknown"')
            
            case "$state" in
                "RUNNING"|"STOPPED")
                    echo -e "${GREEN}$app_name update completed (State: $state)${NC}"
                    return 0
                    ;;
                "DEPLOYING"|"UPDATING")
                    echo -e "${YELLOW}$app_name still updating... (State: $state)${NC}"
                    ;;
                "FAILED"|"ERROR")
                    echo -e "${RED}$app_name update failed (State: $state)${NC}"
                    return 1
                    ;;
                *)
                    echo -e "${YELLOW}$app_name in state: $state${NC}"
                    ;;
            esac
        fi
        
        sleep 10
        wait_time=$((wait_time + 10))
    done
    
    echo -e "${RED}Timeout waiting for $app_name to complete update${NC}"
    return 1
}

# Main function
main() {
    echo -e "${BLUE}TrueNAS Scale App Update Script${NC}"
    echo "================================"
    
    # Check prerequisites
    check_jq
    
    # Test connection
    test_connection
    
    # Get installed apps
    echo -e "${BLUE}Fetching installed applications...${NC}"
    local apps_response=$(api_call "GET" "app")
    
    if [[ $? -ne 0 ]] || [[ -z "$apps_response" ]]; then
        echo -e "${RED}Error: Failed to fetch applications${NC}"
        exit 1
    fi
    
    # Debug: Show first 200 characters of response
    echo -e "${BLUE}API Response (first 200 chars): ${NC}"
    echo "$apps_response" | head -c 200
    echo ""
    
    # Parse apps and check for updates
    local app_count=$(echo "$apps_response" | jq '. | length' 2>/dev/null)
    
    if [[ -z "$app_count" || "$app_count" == "null" ]]; then
        echo -e "${RED}Error: Could not parse app count from API response${NC}"
        echo "This might indicate an API endpoint change or authentication issue"
        exit 1
    fi
    
    if [[ "$app_count" == "0" ]]; then
        echo -e "${YELLOW}No applications found${NC}"
        exit 0
    fi
    
    echo -e "${GREEN}Found $app_count applications${NC}"
    echo ""
    
    local updated_count=0
    local failed_count=0
    
    # Iterate through each app
    for i in $(seq 0 $((app_count - 1))); do
        local app=$(echo "$apps_response" | jq -r ".[$i]")
        local app_id=$(echo "$app" | jq -r '.id')
        local app_name=$(echo "$app" | jq -r '.name // .app_name // .id')
        local state=$(echo "$app" | jq -r '.state // "unknown"')
        
        echo -e "${BLUE}Processing: $app_name (ID: $app_id, State: $state)${NC}"
        
        # Special handling for Plex
        if [[ "$app_id" == "plex" ]]; then
            echo -e "${BLUE}Detected Plex app - checking for active sessions...${NC}"
            
            if ! check_plex_sessions; then
                echo -e "${YELLOW}Plex has active sessions or connection failed.${NC}"
                
                if [[ "$FORCE_UPDATE" == "true" ]]; then
                    echo -e "${YELLOW}Force update enabled - updating Plex anyway${NC}"
                else
                    echo -e "${YELLOW}Skipping Plex update to avoid interrupting active sessions${NC}"
                    echo "Use --force to update anyway, or wait for sessions to end"
                    echo ""
                    continue
                fi
            else
                echo -e "${GREEN}No active Plex sessions - safe to update${NC}"
            fi
        fi
        
        # Check if app is in a state where it can be updated
        if [[ "$state" != "RUNNING" && "$state" != "STOPPED" && "$FORCE_UPDATE" != "true" ]]; then
            echo -e "${YELLOW}Skipping $app_name - not in RUNNING or STOPPED state (Current: $state)${NC}"
            echo "Use --force to update anyway"
            echo ""
            continue
        fi
        
        # Check if update is available (this may not be reliable in all TrueNAS versions)
        local update_available="false"
        if echo "$app" | jq -e '.update_available' >/dev/null 2>&1; then
            update_available=$(echo "$app" | jq -r '.update_available')
        elif echo "$app" | jq -e '.upgrade_available' >/dev/null 2>&1; then
            update_available=$(echo "$app" | jq -r '.upgrade_available')
        fi
        
        if [[ "$update_available" == "true" || "$FORCE_UPDATE" == "true" ]]; then
            if update_app "$app_id" "$app_name"; then
                updated_count=$((updated_count + 1))
            else
                failed_count=$((failed_count + 1))
            fi
        else
            echo -e "${GREEN}$app_name is already up to date${NC}"
        fi
        
        echo ""
    done
    
    # Summary
    echo "================================"
    echo -e "${BLUE}Update Summary:${NC}"
    echo -e "Apps processed: $app_count"
    echo -e "Updates initiated: ${GREEN}$updated_count${NC}"
    echo -e "Failed updates: ${RED}$failed_count${NC}"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${YELLOW}This was a dry run - no actual updates were performed${NC}"
    fi
}

# Run main function
main "$@"

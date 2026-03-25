#!/bin/bash

GOTIFY_URL="https://gotify.domain.com/message?token=GOTIFY_TOKEN_HERE"
MAM_COOKIE_FILE="/config/mam.cookies"
MAM_ID="long________session_______string"
TEMP_BODY="/tmp/mam_response.txt"

# Wait for VPN routing
sleep 5

# -w "%{http_code}" prints the code to stdout
# -o "$TEMP_BODY" saves the JSON/Text response to a file
HTTP_STATUS=$(curl -s -w "%{http_code}" \
    -c "$MAM_COOKIE_FILE" \
    -b "mam_id=$MAM_ID" \
    -o "$TEMP_BODY" \
    "https://t.myanonamouse.net/json/dynamicSeedbox.php")

RESPONSE_BODY=$(cat "$TEMP_BODY")

if [ "$HTTP_STATUS" -ne "200" ]; then
    echo "$(date): MAM IP Update FAILED ($HTTP_STATUS): $RESPONSE_BODY"
    
    # Send to Gotify
    curl -s -X POST "$GOTIFY_URL" \
        -F "title=MAM IP Update Failed ($HTTP_STATUS)" \
        -F "message=MAM Response: $RESPONSE_BODY"
else
    echo "$(date): MAM IP Update Successful: $RESPONSE_BODY"
fi

# Cleanup
rm "$TEMP_BODY"

#!/usr/bin/with-contenv bash

echo "[ProtonVPN Port-Forward] Installing libnatpmp and curl..."
apk add --no-cache libnatpmp curl

# 2. Run the port-forwarding loop in the background so it doesn't block container startup
(
  echo "[ProtonVPN Port-Forward] Waiting for WireGuard (wg-US-CA-474) to connect..."
  while ! ip link show wg-US-CA-474 > /dev/null 2>&1; do
    sleep 5
  done

  UI_PORT=8080
  GATEWAY="10.2.0.1"
  PREV_PORT=0
  GOTIFY_URL="https://gotify.domain.com/message?token=ABCDEFGHIJKLMNOP"
  TEMP_BODY="/tmp/qbit_response.txt"
  NATPMPC_FAILS=0
  NUM_RE='^[0-9]+$'

  while true; do
    # Request port mapping for UDP and TCP
    OUTPUT_UDP=$(natpmpc -a 1 0 udp 60 -g $GATEWAY 2>/dev/null)
    OUTPUT_TCP=$(natpmpc -a 1 0 tcp 60 -g $GATEWAY 2>/dev/null)

    # echo "[ProtonVPN Port-Forward] $OUTPUT_UDP"
    # echo "[ProtonVPN Port-Forward] $OUTPUT_TCP"
    
    # Extract the port numbers from the output
    PORT_UDP=$(echo "$OUTPUT_UDP" | awk '/Mapped public port/ {print $4}')
    PORT_TCP=$(echo "$OUTPUT_TCP" | awk '/Mapped public port/ {print $4}')

    # Validate that ports are numbers
    if [[ $PORT_TCP =~ $NUM_RE ]] && [[ $PORT_UDP =~ $NUM_RE ]] && [[ $PORT_TCP -eq $PORT_UDP ]]; then

      # Reset prev port if there was a failure
      if [[ $NATPMPC_FAILS -gt 0 ]]; then
        PREV_PORT=0
      fi
      NATPMPC_FAILS=0

      if [[ $PORT_TCP != $PREV_PORT ]]; then
        echo "[ProtonVPN Port-Forward] Acquired port $PORT_TCP. Updating qBittorrent..."
        
        # Update qBittorrent listening port via WebAPI
        HTTP_STATUS=$(curl -s -w "%{http_code}" \
            -X POST http://localhost:$UI_PORT/api/v2/app/setPreferences \
            -o "$TEMP_BODY" \
            -d "json={\"listen_port\": $PORT_TCP}")

        RESPONSE_BODY=$(cat "$TEMP_BODY")

        if [[ $HTTP_STATUS != "200" ]]; then
          echo "[ProtonVPN Port-Forward] qBittorrent port:$PORT_TCP update failed! ($HTTP_STATUS): $RESPONSE_BODY"
        else
          echo "[ProtonVPN Port-Forward] qBittorrent port:$PORT_TCP update succeeded! ($HTTP_STATUS): $RESPONSE_BODY"
        fi
        
        PREV_PORT=$PORT_TCP
      fi
    else
      echo "[ProtonVPN Port-Forward] Failed to get port mapping. Retrying in 45s..."
      NATPMPC_FAILS=$((NATPMPC_FAILS + 1))
      if [[ $NATPMPC_FAILS -eq 5 ]]; then
        curl -s -X POST "$GOTIFY_URL" \
            -F "title=qBittorrent (TrueNAS) port mapping failed!" \
            -F "message=NATPMPC Response: $OUTPUT_TCP $OUTPUT_UDP"
      fi
    fi

    # Renew mapping every 45 seconds (ProtonVPN's lease expires every 60 seconds)
    sleep 45
  done
) &

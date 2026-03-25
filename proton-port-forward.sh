#!/usr/bin/with-contenv bash

echo "[ProtonVPN Port-Forward] Installing libnatpmp and curl..."
apk add --no-cache libnatpmp curl

# Run the port-forwarding loop in the background so it doesn't block container startup
(
  echo "[ProtonVPN Port-Forward] Waiting for WireGuard (wg-US-CA-474) to connect..."
  while ! ip link show wg-US-CA-474 > /dev/null 2>&1; do
    sleep 5
  done

  ui_port="8080"
  gateway="10.2.0.1"
  prev_port="0"
  gotify_url="https://gotify.domain.com/message?token=GOTIFY_TOKEN_HERE"
  temp_body="/tmp/qbit_response.txt"
  natpmpc_fails=0
  num_re='^[0-9]+$'

  while true; do
    # Request port mapping for UDP and TCP
    output_udp=$(natpmpc -a 1 0 udp 60 -g "$gateway" 2>/dev/null)
    output_tcp=$(natpmpc -a 1 0 tcp 60 -g "$gateway" 2>/dev/null)

    # Extract the port numbers from the output
    port_udp=$(echo "$output_udp" | awk '/Mapped public port/ {print $4}')
    port_tcp=$(echo "$output_tcp" | awk '/Mapped public port/ {print $4}')

    # Validate that ports are numbers, then verify they match
    if [[ "$port_tcp" =~ $num_re ]] && [[ "$port_udp" =~ $num_re ]] && [[ "$port_tcp" -eq "$port_udp" ]]; then

      # Reset prev port if there was a failure to ensure qBittorrent stays in sync
      if [[ $natpmpc_fails -gt 0 ]]; then
        prev_port="0"
      fi
      natpmpc_fails=0

      if [[ "$port_tcp" != "$prev_port" ]]; then
        echo "[ProtonVPN Port-Forward] Acquired port $port_tcp. Updating qBittorrent..."
        
        # Update qBittorrent listening port via WebAPI
        http_status=$(curl -s -w "%{http_code}" \
            -X POST "http://localhost:${ui_port}/api/v2/app/setPreferences" \
            -o "$temp_body" \
            -d "json={\"listen_port\": $port_tcp}")

        response_body=$(cat "$temp_body")

        if [[ "$http_status" != "200" ]]; then
          echo "[ProtonVPN Port-Forward] qBittorrent port:$port_tcp update failed! ($http_status): $response_body"
        else
          echo "[ProtonVPN Port-Forward] qBittorrent port:$port_tcp update succeeded! ($http_status)"
        fi
        
        prev_port="$port_tcp"
      fi
    else
      echo "[ProtonVPN Port-Forward] Failed to get port mapping. Retrying in 45s..."
      ((natpmpc_fails++))
      
      # Alert exactly on the 5th failure to avoid spamming
      if [[ $natpmpc_fails -eq 5 ]]; then
        curl -s -X POST "$gotify_url" \
            -F "title=qBittorrent (TrueNAS) port mapping failed!" \
            -F "message=NATPMPC Response: $output_tcp $output_udp"
      fi
    fi

    # Renew mapping every 45 seconds (ProtonVPN's lease expires every 60 seconds)
    sleep 45
  done
) &

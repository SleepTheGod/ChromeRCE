#!/bin/bash

# Define URL to check
url="https://www.youtube.com/watch?v=zeIjmvZZ_SQ"

# Path to your Chrome executable (update if necessary)
chromePath="/c/Program Files/Google/Chrome/Application/chrome.exe"

# Define ports for remote debugging and WebSocket server
remoteDebuggingPort=9222
localWebSocketPort=8080

# JavaScript payload to execute remotely
javascriptCode='console.log("Hello from remote JavaScript execution!");'

# Create a temporary directory for the WebSocket server
tempDir=$(mktemp -d)
serverFile="$tempDir/websocket_server.js"

# JavaScript code for the WebSocket server
cat <<EOF > "$serverFile"
const WebSocket = require('ws');
const ws = new WebSocket.Server({ port: $localWebSocketPort });

ws.on('connection', (socket) => {
    socket.on('message', (message) => {
        const jsonCommand = JSON.parse(message);
        const chromeWS = new WebSocket('ws://localhost:$remoteDebuggingPort/devtools/browser/*');

        chromeWS.on('open', () => {
            chromeWS.send(message);
        });

        chromeWS.on('message', (data) => {
            socket.send(data);
        });

        chromeWS.on('error', (error) => {
            console.error('Error:', error);
        });
    });
});

console.log('WebSocket server running on port $localWebSocketPort');
EOF

# Function to launch Chrome with remote debugging enabled
launch_chrome() {
    echo "Launching Chrome with remote debugging enabled..."
    cmd.exe /c start "" "$chromePath" --remote-debugging-port=$remoteDebuggingPort --new-window --incognito "$url"
}

# Function to start the WebSocket server
start_websocket_server() {
    echo "Starting WebSocket server..."
    node "$serverFile" &
    serverPid=$!
    sleep 2
}

# Function to execute JavaScript remotely
execute_javascript() {
    local jsCode="$1"

    # Check if Chrome DevTools is accessible
    devToolsUrl="http://localhost:$remoteDebuggingPort/json"
    response=$(curl -s "$devToolsUrl")

    if [[ -n $response ]]; then
        echo "DevTools URL response received."

        # Find the WebSocket Debugger URL for the specified URL
        chromeEndpoint=$(echo "$response" | jq -r --arg url "$url" '.[] | select(.url | contains($url))')
        if [[ -n $chromeEndpoint ]]; then
            webSocketDebuggerUrl=$(echo "$chromeEndpoint" | jq -r '.webSocketDebuggerUrl')

            if [[ -n $webSocketDebuggerUrl ]]; then
                echo "WebSocket Debugger URL: $webSocketDebuggerUrl"

                # Create the JSON payload for WebSocket communication
                jsonCommand=$(cat <<EOF
{
    "id": 1,
    "method": "Runtime.evaluate",
    "params": {
        "expression": "$jsCode",
        "returnByValue": true
    }
}
EOF
)

                # Send JavaScript code via local WebSocket server using websocat
                echo "$jsonCommand" | websocat "ws://localhost:$localWebSocketPort"
                echo "JavaScript code executed."
            else
                echo "Failed to retrieve WebSocket Debugger URL."
            fi
        else
            echo "Chrome process for the specified URL not found."
        fi
    else
        echo "Could not access DevTools URL: $devToolsUrl"
    fi
}

# Ensure Node.js is installed
if ! command -v node &> /dev/null; then
    echo "Node.js is not installed. Please install Node.js to run this script."
    exit 1
fi

# Ensure websocat is installed
if ! command -v websocat &> /dev/null; then
    echo "websocat is not installed. Please install websocat to run this script."
    exit 1
fi

# Launch Chrome
launch_chrome

# Start the WebSocket server
start_websocket_server

# Wait for Chrome to start and load the page
sleep 15  # Adjust as needed

# Execute the JavaScript code
execute_javascript "$javascriptCode"

# Clean up
kill $serverPid
rm -rf "$tempDir"

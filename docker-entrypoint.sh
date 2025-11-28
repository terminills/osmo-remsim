#!/bin/bash
# Docker entrypoint script for osmo-remsim
#
# Usage:
#   docker run osmo-remsim server           # Run remsim-server
#   docker run osmo-remsim bankd            # Run remsim-bankd
#   docker run osmo-remsim client           # Run remsim-client (shell)
#   docker run osmo-remsim pcscd            # Run PC/SC daemon only
#   docker run osmo-remsim all              # Run server + bankd (for testing)

set -e

# Function to start pcscd if not running
start_pcscd() {
    if ! pgrep -x pcscd > /dev/null; then
        echo "Starting PC/SC daemon..."
        pcscd --foreground &
        sleep 1
    fi
}

# Function to list available PC/SC readers
list_readers() {
    echo "Available PC/SC readers:"
    pcsc_scan -r 2>/dev/null || echo "No readers found or pcsc_scan not available"
}

case "$1" in
    server)
        echo "Starting osmo-remsim-server..."
        exec /usr/local/bin/osmo-remsim-server "${@:2}"
        ;;
    
    bankd)
        # Start pcscd for smart card access
        start_pcscd
        
        # Build bankd options from environment variables
        BANKD_OPTS=""
        
        if [ -n "$REMSIM_SERVER_HOST" ]; then
            BANKD_OPTS="$BANKD_OPTS -i $REMSIM_SERVER_HOST"
        else
            echo "Error: REMSIM_SERVER_HOST environment variable is required"
            echo "Usage: docker run -e REMSIM_SERVER_HOST=<server-ip> osmo-remsim bankd"
            exit 1
        fi
        
        if [ -n "$REMSIM_SERVER_PORT" ]; then
            BANKD_OPTS="$BANKD_OPTS -p $REMSIM_SERVER_PORT"
        fi
        
        if [ -n "$REMSIM_BANK_ID" ]; then
            BANKD_OPTS="$BANKD_OPTS -b $REMSIM_BANK_ID"
        fi
        
        if [ -n "$REMSIM_NUM_SLOTS" ]; then
            BANKD_OPTS="$BANKD_OPTS -n $REMSIM_NUM_SLOTS"
        fi
        
        if [ -n "$REMSIM_BIND_IP" ]; then
            BANKD_OPTS="$BANKD_OPTS -I $REMSIM_BIND_IP"
        fi
        
        if [ -n "$REMSIM_BIND_PORT" ]; then
            BANKD_OPTS="$BANKD_OPTS -P $REMSIM_BIND_PORT"
        fi
        
        echo "Starting osmo-remsim-bankd with options: $BANKD_OPTS ${*:2}"
        exec /usr/local/bin/osmo-remsim-bankd $BANKD_OPTS "${@:2}"
        ;;
    
    client)
        echo "Starting osmo-remsim-client-shell..."
        exec /usr/local/bin/osmo-remsim-client-shell "${@:2}"
        ;;
    
    pcscd)
        echo "Starting PC/SC daemon in foreground..."
        list_readers
        exec pcscd --foreground "${@:2}"
        ;;
    
    all)
        # Run both server and bankd (useful for testing)
        echo "Starting all services (server + bankd)..."
        start_pcscd
        
        # Start server in background
        /usr/local/bin/osmo-remsim-server &
        SERVER_PID=$!
        
        # Wait for server to be ready
        sleep 2
        
        # Start bankd
        BANKD_OPTS="-i 127.0.0.1"
        
        if [ -n "$REMSIM_BANK_ID" ]; then
            BANKD_OPTS="$BANKD_OPTS -b $REMSIM_BANK_ID"
        fi
        
        if [ -n "$REMSIM_NUM_SLOTS" ]; then
            BANKD_OPTS="$BANKD_OPTS -n $REMSIM_NUM_SLOTS"
        fi
        
        echo "Starting bankd with options: $BANKD_OPTS"
        /usr/local/bin/osmo-remsim-bankd $BANKD_OPTS &
        BANKD_PID=$!
        
        # Wait for either process to exit
        wait -n $SERVER_PID $BANKD_PID
        
        # If we get here, one of the processes died
        echo "A service has exited, shutting down..."
        kill $SERVER_PID $BANKD_PID 2>/dev/null || true
        exit 1
        ;;
    
    list-readers)
        start_pcscd
        list_readers
        ;;
    
    shell|bash)
        exec /bin/bash "${@:2}"
        ;;
    
    -h|--help|help)
        cat << EOF
osmo-remsim Docker Image

Usage: docker run [docker-options] osmo-remsim <command> [options]

Commands:
  server        Run the remsim-server (default)
  bankd         Run the remsim-bankd (SIM bank daemon)
  client        Run the remsim-client-shell
  pcscd         Run PC/SC daemon only
  all           Run server + bankd together (for testing)
  list-readers  List available PC/SC readers
  shell         Start a bash shell
  help          Show this help message

Environment Variables:
  REMSIM_SERVER_HOST    Server hostname/IP (required for bankd)
  REMSIM_SERVER_PORT    Server port (default: 9998)
  REMSIM_BANK_ID        Bank ID (default: 1)
  REMSIM_NUM_SLOTS      Number of SIM slots (default: 8)
  REMSIM_BIND_IP        Bind IP for bankd (default: all interfaces)
  REMSIM_BIND_PORT      Bind port for bankd (default: 9999)

Examples:
  # Run server only
  docker run -d --name remsim-server -p 9997:9997 -p 9998:9998 osmo-remsim

  # Run bankd with USB access (octosim reader)
  docker run -d --name remsim-bankd \\
    --privileged \\
    -v /dev/bus/usb:/dev/bus/usb \\
    -e REMSIM_SERVER_HOST=192.168.1.100 \\
    osmo-remsim bankd

  # Run both server and bankd together
  docker run -d --name remsim-all \\
    --privileged \\
    -v /dev/bus/usb:/dev/bus/usb \\
    -p 9997:9997 -p 9998:9998 -p 9999:9999 \\
    osmo-remsim all

EOF
        ;;
    
    *)
        # If no recognized command, assume it's a direct binary execution
        if [ -x "/usr/local/bin/$1" ]; then
            exec "/usr/local/bin/$1" "${@:2}"
        else
            echo "Unknown command: $1"
            echo "Run with 'help' for usage information"
            exit 1
        fi
        ;;
esac

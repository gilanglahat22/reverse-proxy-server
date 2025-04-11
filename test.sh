#!/usr/bin/env bash
#
# Kantara Reverse Proxy Test Script
# Tests both web server and reverse proxy functionality
#

set -eo pipefail  # Exit on error, undefined vars, and propagate pipe failures

# Configuration
WEB_PORT=3000
PROXY_PORT=8080
SERVER_BINARY="target/debug/kantara-proxy"
EXPECTED_RESPONSE="Hello, World!"
TIMEOUT=5  # Seconds to wait for server to start
USE_PINGORA=false

# ANSI colors for better readability
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Parse command line arguments
for arg in "$@"; do
    case $arg in
        --use-pingora)
            USE_PINGORA=true
            shift
            ;;
    esac
done

# Function to print a section header
print_header() {
    echo -e "\n${BLUE}$1${NC}"
    echo -e "${BLUE}${1//?/=}${NC}\n"
}

# Function to execute tests and print results
run_test() {
    local name="$1"
    local url="$2"
    local expected="$3"
    
    echo -n "Testing $name... "
    local response
    response=$(curl -s "$url")
    
    if [[ "$response" == "$expected" ]]; then
        echo -e "${GREEN}✓ $name working correctly${NC}"
        echo -e "  Expected: $expected"
        echo -e "  Received: $response"
        return 0
    else
        echo -e "${RED}✗ $name test failed${NC}"
        echo -e "  Expected: $expected"
        echo -e "  Received: $response"
        return 1
    fi
}

# Function to check if a port is in use
check_port() {
    nc -z localhost "$1" >/dev/null 2>&1
    return $?
}

# Function to clean up resources
cleanup() {
    print_header "Cleaning up"
    if [[ -n "$SERVER_PID" ]]; then
        echo "Stopping server (PID: $SERVER_PID)..."
        kill "$SERVER_PID" 2>/dev/null || true
        wait "$SERVER_PID" 2>/dev/null || true
    fi
    echo -e "${GREEN}Done${NC}"
}

# Set up trap to clean up on exit
trap cleanup EXIT INT TERM

# Main execution
print_header "Building application"
cargo build || { echo -e "${RED}Build failed${NC}"; exit 1; }

print_header "Starting server"
# Start the server with default ports
echo "Starting server with default ports..."

if [[ "$USE_PINGORA" == true ]]; then
    echo "Using Pingora backend for reverse proxy"
    RUST_LOG=info "$SERVER_BINARY" --web-port "$WEB_PORT" --proxy-port "$PROXY_PORT" --use-pingora > server_test.log 2>&1 &
else
    echo "Using Actix Web backend for reverse proxy (default)"
    RUST_LOG=info "$SERVER_BINARY" --web-port "$WEB_PORT" --proxy-port "$PROXY_PORT" > server_test.log 2>&1 &
fi

SERVER_PID=$!

# Give the server time to start
echo "Server started with PID: $SERVER_PID"
echo "Waiting for server to initialize..."

# Wait for the server to be ready
for ((i=1; i<=TIMEOUT; i++)); do
    # Check if the server is still running
    if ! ps -p "$SERVER_PID" > /dev/null; then
        echo -e "${RED}Server failed to start!${NC}"
        cat server_test.log
        exit 1
    fi
    
    # Check if the ports are listening
    WEB_READY=false
    PROXY_READY=false
    
    if check_port "$WEB_PORT"; then
        WEB_READY=true
    fi
    
    if check_port "$PROXY_PORT"; then
        PROXY_READY=true
    fi
    
    # If both ports are ready, break out of the loop
    if $WEB_READY && $PROXY_READY; then
        echo -e "${GREEN}Server is ready!${NC}"
        echo "Web server running on port: $WEB_PORT"
        echo "Reverse proxy running on port: $PROXY_PORT"
        if [[ "$USE_PINGORA" == true ]]; then
            echo "Using Pingora backend"
        else
            echo "Using Actix Web backend"
        fi
        break
    fi
    
    if [[ $i -eq $TIMEOUT ]]; then
        echo -e "${YELLOW}Warning: Server may not be fully initialized within $TIMEOUT seconds${NC}"
        echo "Continuing with tests anyway..."
        cat server_test.log
    else
        echo "Waiting... ($i/$TIMEOUT)"
        sleep 1
    fi
done

# Run tests
print_header "Running tests"
WEB_TEST_RESULT=0
PROXY_TEST_RESULT=0

run_test "web server" "http://localhost:$WEB_PORT" "$EXPECTED_RESPONSE" || WEB_TEST_RESULT=1
run_test "reverse proxy" "http://localhost:$PROXY_PORT" "$EXPECTED_RESPONSE" || PROXY_TEST_RESULT=1

# Test random path to ensure all paths work
run_test "web server with path" "http://localhost:$WEB_PORT/random/path" "$EXPECTED_RESPONSE" || WEB_TEST_RESULT=1
run_test "reverse proxy with path" "http://localhost:$PROXY_PORT/random/path" "$EXPECTED_RESPONSE" || PROXY_TEST_RESULT=1

# Report results
print_header "Test results"
if [[ $WEB_TEST_RESULT -eq 0 && $PROXY_TEST_RESULT -eq 0 ]]; then
    echo -e "${GREEN}All tests passed successfully!${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed.${NC}"
    exit 1
fi 
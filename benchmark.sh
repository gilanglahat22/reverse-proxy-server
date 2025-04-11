#!/bin/bash
#
# Kantara Reverse Proxy Benchmarking Tool
# Measures performance of both web server and reverse proxy
#

set -eo pipefail

# ANSI colors for better readability
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Default configuration
CONFIG=(
  ["duration"]=30
  ["connections"]=400
  ["threads"]=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)
  ["url"]="http://localhost:8080"
)

# Function to print a section header
print_header() {
  echo -e "\n${BLUE}$1${NC}"
  echo -e "${BLUE}${1//?/=}${NC}\n"
}

# Function to print error and exit
error() {
  echo -e "${RED}ERROR: $1${NC}" >&2
  exit 1
}

# Function to show help/usage
show_help() {
  cat << EOF
Usage: $(basename "$0") [options]

Benchmark the Kantara Reverse Proxy server performance.

Options:
  -d, --duration N    Duration of the test in seconds (default: ${CONFIG["duration"]})
  -c, --connections N Number of connections to keep open (default: ${CONFIG["connections"]})
  -t, --threads N     Number of threads to use (default: ${CONFIG["threads"]})
  -u, --url URL       URL to benchmark (default: ${CONFIG["url"]})
  -h, --help          Show this help message

Examples:
  $(basename "$0") --url http://localhost:8080 --duration 10
  $(basename "$0") -t 8 -c 200 -d 60
EOF
  exit 0
}

# Check if dependencies are installed
check_dependencies() {
  print_header "Checking Dependencies"
  
  if ! command -v curl &> /dev/null; then
    echo -e "${YELLOW}Required tool 'curl' is not installed.${NC}"
    echo -e "Please install it using one of the following methods:"
    echo -e "  - macOS:         ${GREEN}brew install curl${NC}"
    echo -e "  - Ubuntu/Debian: ${GREEN}sudo apt-get install curl${NC}"
    echo -e "  - From source:   ${GREEN}https://curl.se/download.html${NC}"
    error "Missing required dependency: curl"
  fi
  
  echo -e "${GREEN}✓ All dependencies are installed${NC}"
}

# Parse command line arguments
parse_args() {
  while [[ $# -gt 0 ]]; do
    case $1 in
      -d|--duration)
        CONFIG["duration"]="$2"
        shift 2
        ;;
      -c|--connections)
        CONFIG["connections"]="$2"
        shift 2
        ;;
      -t|--threads)
        CONFIG["threads"]="$2"
        shift 2
        ;;
      -u|--url)
        CONFIG["url"]="$2"
        shift 2
        ;;
      -h|--help)
        show_help
        ;;
      *)
        error "Unknown option: $1\nUse --help for usage information"
        ;;
    esac
  done
}

# Run the benchmark
run_benchmark() {
  print_header "Benchmark Configuration"
  echo -e "Duration:    ${BLUE}${CONFIG["duration"]} seconds${NC}"
  echo -e "Connections: ${BLUE}${CONFIG["connections"]}${NC}"
  echo -e "Threads:     ${BLUE}${CONFIG["threads"]}${NC}"
  echo -e "URL:         ${BLUE}${CONFIG["url"]}${NC}"
  
  print_header "Running Benchmark"
  echo -e "Starting benchmark..."
  echo
  
  # Find the proxy port
  echo "Checking if Kantara Proxy is running..."
  PROXY_PORT=8080
  WEB_PORT=3000

  # Function to check if a port is in use
  check_port() {
    nc -z localhost $1 > /dev/null 2>&1
    return $?
  }

  # Check if the proxy is running on the default port
  if ! check_port $PROXY_PORT; then
    echo -e "${YELLOW}Proxy not found on port $PROXY_PORT. Scanning common ports...${NC}"
    
    # Try some alternative ports
    for port in 8080 8000 80 3000 3001 8080 8282; do
      if check_port $port; then
        # Make a request to see if it's the proxy
        response=$(curl -s http://localhost:$port)
        if [[ "$response" == "Hello, World!" ]]; then
          PROXY_PORT=$port
          echo -e "${GREEN}Found proxy running on port $PROXY_PORT${NC}"
          break
        fi
      fi
    done
    
    if ! check_port $PROXY_PORT; then
      echo -e "${RED}Error: Could not find a running Kantara Proxy server.${NC}"
      echo "Please start the server with: cargo run"
      exit 1
    fi
  fi

  # Warm up the server
  echo "Warming up the server..."
  for i in {1..10}; do
    curl -s http://localhost:$PROXY_PORT > /dev/null
  done

  # Run benchmark
  TOTAL_REQUESTS=5000
  CONCURRENT=100
  START_TIME=$(date +%s.%N)

  echo "Starting benchmark:"
  echo "- Total requests: $TOTAL_REQUESTS"
  echo "- Concurrent requests: $CONCURRENT"
  echo "- Target URL: http://localhost:$PROXY_PORT"
  echo

  # Check if we can use GNU parallel for better performance
  if command -v parallel &> /dev/null; then
    echo "Using GNU parallel for benchmarking..."
    
    # Create a temp file with URLs
    TEMP_FILE=$(mktemp)
    for i in $(seq 1 $TOTAL_REQUESTS); do
      echo "http://localhost:$PROXY_PORT" >> $TEMP_FILE
    done
    
    # Run the benchmark using parallel
    parallel -j $CONCURRENT -a $TEMP_FILE curl -s > /dev/null
    
    # Clean up
    rm $TEMP_FILE
  else
    echo "Using basic bash for benchmarking (install GNU parallel for better performance)..."
    
    # Basic approach using background processes
    for i in $(seq 1 $TOTAL_REQUESTS); do
      # Start CONCURRENT requests in parallel
      if (( i % CONCURRENT == 0 )); then
        # Wait for all background jobs to complete
        wait
      fi
      curl -s http://localhost:$PROXY_PORT > /dev/null &
    done
    
    # Wait for any remaining requests
    wait
  fi

  END_TIME=$(date +%s.%N)
  DURATION=$(echo "$END_TIME - $START_TIME" | bc)
  RPS=$(echo "$TOTAL_REQUESTS / $DURATION" | bc)

  echo
  echo "Benchmark complete!"
  echo "====================================="
  echo "Total time: $DURATION seconds"
  echo "Requests per second: $RPS"

  # Check if RPS meets the requirement
  if (( $(echo "$RPS >= 1000" | bc -l) )); then
    echo -e "${GREEN}✓ PASS: Server can handle more than 1000 requests per second${NC}"
  else
    echo -e "${RED}✗ FAIL: Server handled less than 1000 requests per second${NC}"
  fi

  echo
  echo "To run the server with different ports:"
  echo "  cargo run -- --web-port 3000 --proxy-port 8080"
}

# Main execution
print_header "Kantara Reverse Proxy Benchmarking Tool"

# Process arguments
parse_args "$@"

# Check dependencies
check_dependencies

# Run benchmark
run_benchmark 
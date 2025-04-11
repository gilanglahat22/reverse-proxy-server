#!/bin/bash

# Set the target URL
TARGET_URL=${1:-"http://localhost:8081"}
REQUESTS=1000
CONCURRENCY=100

echo "========================================"
echo "Simple Performance Test for Kantara Proxy"
echo "========================================"
echo "Target: $TARGET_URL"
echo "Requests: $REQUESTS"
echo "Concurrency: $CONCURRENCY"
echo "========================================"

# Check if ab is available
if command -v ab &> /dev/null; then
    echo "Using ApacheBench (ab) for testing..."
    ab -n $REQUESTS -c $CONCURRENCY $TARGET_URL
elif command -v curl &> /dev/null; then
    echo "Using curl for testing (less accurate)..."
    
    START_TIME=$(date +%s.%N)
    
    # Run curl in a loop
    for i in $(seq 1 $REQUESTS); do
        if (( i % 10 == 0 )); then
            echo -ne "$i/$REQUESTS requests completed\r"
        fi
        curl -s $TARGET_URL > /dev/null
    done
    
    END_TIME=$(date +%s.%N)
    DURATION=$(echo "$END_TIME - $START_TIME" | bc)
    
    echo "Completed $REQUESTS requests in $DURATION seconds"
    echo "Requests per second: $(echo "$REQUESTS / $DURATION" | bc)"
else
    echo "Error: Neither 'ab' nor 'curl' found. Please install one of these tools."
    exit 1
fi 
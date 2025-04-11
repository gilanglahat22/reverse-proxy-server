# Kantara Reverse Proxy HTTP Server

A high-performance reverse proxy implementation in Rust consisting of two components:

1. A simple web server on port 3000 that responds with "Hello, World!" for all HTTP requests
2. A reverse proxy server on port 8080 (configurable to port 80) that forwards requests to the web server

## Project Requirements

This application satisfies the following requirements:

- Web server runs on port 3000 and returns "Hello World" for HTTP GET requests
- Reverse proxy server runs on port 8080 (or port 80) and forwards to the web server
- Both components are implemented in Rust
- Capable of handling at least 1000 requests per second
- Includes a benchmarking tool to verify performance

## Features

- High-performance web server and reverse proxy
- Built with Actix Web for efficient request handling
- Automatic port selection if requested ports are in use
- Complete request/response forwarding with header preservation
- Simple command-line configuration options

## Pingora Integration

The project includes experimental support for Cloudflare's Pingora, a high-performance HTTP proxy framework. While the primary implementation uses Actix Web, you can try the Pingora backend with:

```
./target/release/kantara-proxy --use-pingora
```

Note: Pingora integration may require additional dependencies and is considered experimental.

## Requirements

- Rust and Cargo (latest stable version)

## Installation

1. If you don't have Rust installed, install it first:
   ```
   curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
   source "$HOME/.cargo/env"
   ```

2. Clone the repository:
   ```
   git clone https://bitbucket.org/kantara/reverse-proxy.git
   cd reverse-proxy
   ```

3. Build the project:
   ```
   cargo build --release
   ```

## Running

To run the application with default settings (web server on port 3000, proxy on port 8080):

```
./target/release/kantara-proxy
```

You can customize the ports and upstream URL:

```
./target/release/kantara-proxy --web-port 3000 --proxy-port 8080 --upstream http://127.0.0.1:3000
```

To run the proxy on port 80 (as specified in requirements):

```
sudo ./target/release/kantara-proxy --proxy-port 80
```

This will start:
- A web server on http://0.0.0.0:3000
- A reverse proxy on http://0.0.0.0:8080 (or port 80, or your custom port) forwarding to the web server

### Auto-Port Selection

By default, if a requested port is already in use, the application will automatically search for an available port starting from the requested port + 1. If you want to disable this behavior and have the application fail if a port is not available, use the `--no-auto-port` flag:

```
./target/release/kantara-proxy --no-auto-port
```

## Testing

You can test the reverse proxy by accessing:
```
curl http://localhost:8080
```

You should see the response: `Hello, World!`

You can also test the web server directly:
```
curl http://localhost:3000
```

For more extensive functional testing, use the provided test script:
```
./test.sh
```

To test with the Pingora backend:
```
./test.sh --use-pingora
```

## Performance Testing

For benchmarking the server's performance:

```
./benchmark.sh
```

This comprehensive benchmark script tests the server's ability to handle a high load, with detailed output and verification that the server meets the requirement of handling at least 1000 requests per second.

For a simpler benchmark test:
```
./simple_benchmark.sh
```

You can also use tools like `wrk` or `ab` (Apache Benchmark) to test performance:

```
# Using wrk (if installed)
wrk -t12 -c400 -d30s http://localhost:8080

# Using ab (Apache Benchmark)
ab -n 10000 -c 100 http://localhost:8080/
```

## Troubleshooting

### Permission Denied Error

If you get a "Permission denied" error when binding to a low port (< 1024), it's because these ports require administrator/root privileges. Use sudo or choose a higher port number.

### Address Already in Use Error

If you get an "Address already in use" error and you're not using the `--no-auto-port` flag, the application will automatically try to find an available port. If you're using `--no-auto-port` and get this error, try a different port:

```
./target/release/kantara-proxy --web-port 3001 --proxy-port 8282
```

### Build Errors

If you encounter build errors, make sure you have the latest Rust toolchain:

```
rustup update
```

## Project Structure

- `src/main.rs`: Main application code containing both the web server and reverse proxy implementation
- `benchmark.sh`: Comprehensive script for performance testing
- `simple_benchmark.sh`: Simple alternative benchmark script
- `test.sh`: Script for functional testing

## License

[MIT License](LICENSE)

## Author

Muhammad Gilang Ramadhan - muhgilangramadhan.3011@gmail.com # reverse-proxy-server

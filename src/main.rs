use actix_web::{web, App, HttpRequest, HttpResponse, HttpServer, Responder};
use clap::Parser;
use log::{error, info, warn};
use std::{io, net::{TcpListener, SocketAddr}};
use reqwest;
use futures_util;

/// Kantara Reverse Proxy
///
/// A simple web server and reverse proxy implementation in Rust.
/// - Web server: Serves "Hello, World!" on the configured port
/// - Reverse Proxy: Forwards requests to the web server
#[derive(Parser, Debug)]
#[clap(
    version,
    about = "High-performance web server and reverse proxy",
    long_about = None
)]
struct Args {
    /// Port for the web server to listen on
    #[clap(short, long, default_value = "3000")]
    web_port: u16,

    /// Port for the reverse proxy to listen on
    #[clap(short, long, default_value = "8080")]
    proxy_port: u16,

    /// Upstream server URL for the reverse proxy
    #[clap(short, long, default_value = "http://127.0.0.1:3000")]
    upstream: String,
    
    /// Disable auto-finding available ports if specified ports are in use
    #[clap(short, long)]
    no_auto_port: bool,
}

/// Simple handler for the web server that returns "Hello, World!"
async fn hello_world(_req: HttpRequest) -> impl Responder {
    HttpResponse::Ok().body("Hello, World!")
}

/// Reverse proxy handler that forwards requests to the upstream server
async fn proxy_handler(req: HttpRequest, body: web::Bytes) -> impl Responder {
    // Get the upstream URL from application data
    let upstream_url = req.app_data::<web::Data<String>>()
        .map(|config| config.as_str())
        .unwrap_or("http://127.0.0.1:3000");

    // Extract the path and query from the request
    let path = req.uri().path_and_query().map_or("", |p| p.as_str());
    
    // Form the complete URL
    let url = format!("{}{}", upstream_url, path);
    
    info!("Proxying request to: {}", url);
    
    // Create a reqwest client for making HTTP requests
    let client = match reqwest::Client::builder()
        .build() {
            Ok(client) => client,
            Err(e) => {
                error!("Failed to create HTTP client: {}", e);
                return HttpResponse::InternalServerError().body(format!("Failed to create HTTP client: {}", e));
            }
        };
    
    // Build the request to the upstream server
    let mut request_builder = client.request(
        req.method().clone(), 
        &url
    );
    
    // Copy all headers from the original request
    for (header_name, header_value) in req.headers() {
        // Skip the host header as it needs to be set for the upstream server
        if header_name != "host" && header_name != "content-length" {
            request_builder = request_builder.header(header_name, header_value);
        }
    }
    
    // Add the request body if present
    if !body.is_empty() {
        request_builder = request_builder.body(body);
    }
    
    // Send the request to the upstream server
    match request_builder.send().await {
        Ok(response) => {
            // Start building the response to the client
            let mut client_response_builder = HttpResponse::build(response.status());
            
            // Copy headers from the upstream response
            for (header_name, header_value) in response.headers() {
                if header_name != "transfer-encoding" {
                    client_response_builder.insert_header((header_name.clone(), header_value.clone()));
                }
            }
            
            // Get the response body
            match response.bytes().await {
                Ok(bytes) => {
                    // Return the response from the upstream server
                    client_response_builder.body(bytes)
                },
                Err(e) => {
                    error!("Failed to get response body: {}", e);
                    HttpResponse::InternalServerError().body(format!("Failed to get response body: {}", e))
                }
            }
        },
        Err(e) => {
            error!("Failed to send request to upstream server: {}", e);
            HttpResponse::BadGateway().body(format!("Failed to send request to upstream server: {}", e))
        }
    }
}

/// Check if a port is available
fn is_port_available(port: u16) -> bool {
    TcpListener::bind(SocketAddr::from(([127, 0, 0, 1], port))).is_ok()
        && TcpListener::bind(SocketAddr::from(([0, 0, 0, 0], port))).is_ok()
}

/// Find an available port starting from the given port
fn find_available_port(start_port: u16) -> Option<u16> {
    // Try a wider range of ports (up to 1000 ports from start)
    // This gives us more options if there are many ports in use
    for port in start_port..start_port.saturating_add(1000) {
        if is_port_available(port) {
            return Some(port);
        }
    }
    None
}

/// Configure and start the web server
fn start_web_server(port: u16, auto_port: bool) -> io::Result<(actix_web::dev::Server, u16)> {
    info!("Configuring web server on port {}", port);
    
    let bind_result = HttpServer::new(|| {
        App::new()
            .route("/", web::get().to(hello_world))
            .route("/{tail:.*}", web::get().to(hello_world))
    })
    .workers(num_cpus::get())
    .bind(("0.0.0.0", port));
    
    match bind_result {
        Ok(server) => {
            let server = server.run();
            Ok((server, port))
        },
        Err(e) if auto_port => {
            // Try to find an alternative port
            warn!("Failed to bind web server to port {}: {}", port, e);
            if let Some(alt_port) = find_available_port(port + 1) {
                info!("Using alternative port {} for web server", alt_port);
                let server = HttpServer::new(|| {
                    App::new()
                        .route("/", web::get().to(hello_world))
                        .route("/{tail:.*}", web::get().to(hello_world))
                })
                .workers(num_cpus::get())
                .bind(("0.0.0.0", alt_port))?
                .run();
                Ok((server, alt_port))
            } else {
                error!("Could not find any available ports for web server");
                Err(io::Error::new(
                    io::ErrorKind::AddrInUse,
                    format!("Failed to bind to port {} and could not find any alternative ports. Try manually specifying a different port with --web-port.", port)
                ))
            }
        },
        Err(e) => {
            error!("Failed to bind web server to port {}: {}", port, e);
            Err(e)
        }
    }
}

/// Configure and start the reverse proxy server
fn start_proxy_server(port: u16, upstream: web::Data<String>, auto_port: bool) -> io::Result<(actix_web::dev::Server, u16)> {
    info!("Configuring reverse proxy on port {} pointing to {}", port, upstream.as_ref());
    
    let upstream_clone = upstream.clone();
    let bind_result = HttpServer::new(move || {
        App::new()
            .app_data(upstream_clone.clone())
            .default_service(web::to(proxy_handler))
    })
    .workers(num_cpus::get())
    .bind(("0.0.0.0", port));
    
    match bind_result {
        Ok(server) => {
            let server = server.run();
            Ok((server, port))
        },
        Err(e) if auto_port => {
            // Try to find an alternative port
            warn!("Failed to bind proxy server to port {}: {}", port, e);
            if let Some(alt_port) = find_available_port(port + 1) {
                info!("Using alternative port {} for proxy server", alt_port);
                // Create a new clone for the new HttpServer
                let upstream_clone2 = upstream.clone();
                let server = HttpServer::new(move || {
                    App::new()
                        .app_data(upstream_clone2.clone())
                        .default_service(web::to(proxy_handler))
                })
                .workers(num_cpus::get())
                .bind(("0.0.0.0", alt_port))?
                .run();
                Ok((server, alt_port))
            } else {
                error!("Could not find any available ports for proxy server");
                Err(io::Error::new(
                    io::ErrorKind::AddrInUse,
                    format!("Failed to bind to port {} and could not find any alternative ports. Try manually specifying a different port with --proxy-port.", port)
                ))
            }
        },
        Err(e) => {
            error!("Failed to bind proxy server to port {}: {}", port, e);
            Err(e)
        }
    }
}

/// Initialize the application logger
fn init_logger() {
    if std::env::var("RUST_LOG").is_err() {
        std::env::set_var("RUST_LOG", "info");
    }
    env_logger::init();
}

/// Print a welcome message with server information
fn print_welcome_message(web_port: u16, proxy_port: u16) {
    println!("\n✓ Kantara Proxy is running!");
    println!("  - Web server: http://localhost:{}", web_port);
    println!("  - Reverse proxy: http://localhost:{}", proxy_port);
    println!("  - Press Ctrl+C to stop\n");
    
    info!("Web server running at http://localhost:{}", web_port);
    info!("Reverse proxy running at http://localhost:{}", proxy_port);
    info!("Server is ready! Press Ctrl+C to stop.");
}

#[actix_web::main]
async fn main() -> io::Result<()> {
    // Initialize the logger
    init_logger();

    // Parse command line arguments
    let args = Args::parse();
    
    info!("Starting Kantara Reverse Proxy");
    info!("Web server port: {} (requested)", args.web_port);
    info!("Reverse proxy port: {} (requested)", args.proxy_port);
    info!("Upstream URL: {}", args.upstream);
    
    let auto_port = !args.no_auto_port;
    if auto_port {
        info!("Auto-port selection enabled: will try alternative ports if specified ports are in use");
    } else {
        info!("Auto-port selection disabled: will not try alternative ports if specified ports are in use");
    }

    // Start web server
    let (web_server, actual_web_port) = start_web_server(args.web_port, auto_port)?;
    
    // Update upstream URL with actual web port if it changed
    let upstream_url = if actual_web_port != args.web_port && args.upstream.contains(&args.web_port.to_string()) {
        args.upstream.replace(&args.web_port.to_string(), &actual_web_port.to_string())
    } else {
        args.upstream.clone()
    };
    
    // Create shared upstream URL data
    let upstream = web::Data::new(upstream_url);
    
    // Start reverse proxy server
    let (proxy_server, actual_proxy_port) = start_proxy_server(args.proxy_port, upstream, auto_port)?;

    // Print welcome message
    print_welcome_message(actual_web_port, actual_proxy_port);

    // Run both servers concurrently
    futures_util::future::try_join(web_server, proxy_server).await?;

    Ok(())
}

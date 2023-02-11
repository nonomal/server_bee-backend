#![cfg_attr(feature = "subsystem", windows_subsystem = "windows")]

use cli::Args;
use crate::config::Config;

use actix_web::{middleware, web, App, Error, HttpRequest, HttpResponse, HttpServer};
use actix_web_actors::ws;
use clap::Parser;
use log::info;
use crate::http_handler::{index, kill_process, version};

mod cli;
mod config;
mod model;
mod server;
mod system_info;
mod vo;
mod http_handler;
mod term;

use self::server::MyWebSocket;

/// WebSocket handshake and start `MyWebSocket` actor.
async fn echo_ws(req: HttpRequest, stream: web::Payload) -> Result<HttpResponse, Error> {
    ws::start(MyWebSocket::new(), &req, stream)
}

#[actix_web::main]
async fn main() -> std::io::Result<()> {

    let args = Args::parse();

    Config::init_logging(args.log_path);

    let port =
        args.port.unwrap_or_else(Config::get_server_port);

    info!("starting HTTP server at http://localhost:{}", port);

    HttpServer::new(|| {
        App::new()
            .service(web::resource("/").to(index))
            .service(web::resource("/version").to(version))
            .service(kill_process)
            // websocket route
            .service(web::resource("/ws").route(web::get().to(echo_ws)))
            // enable logger
            .wrap(middleware::Logger::default())
    })
    .workers(2)
    .bind(("0.0.0.0", port))?
    .run()
    .await
}

use std::io::Write;
use std::process::Command;
use std::time::{Duration, Instant};

use actix::prelude::*;
use actix_codec::{BytesCodec, Decoder, Framed};

use actix_web_actors::ws;

use log::{error, info, trace, warn};
use tokio_pty_process::{AsyncPtyMaster, AsyncPtyMasterWriteHalf, Child, CommandExt};
use crate::term::event;

/// How often heartbeat pings are sent
const HEARTBEAT_INTERVAL: Duration = Duration::from_secs(5);

const TASK_INTERVAL: Duration = Duration::from_secs(1);

/// How long before lack of client response causes a timeout
const CLIENT_TIMEOUT: Duration = Duration::from_secs(10);


pub struct TermSocket {
    cons: Option<Addr<Terminal>>,
    hb: Instant,
    command: Option<Command>,
}

impl TermSocket {
    pub fn new(command: Command) -> Self {
        Self {
            hb: Instant::now(),
            cons: None,
            command: Some(command),
        }
    }
}

impl Actor for TermSocket {
    type Context = ws::WebsocketContext<Self>;

    fn started(&mut self, ctx: &mut Self::Context) {
        let command = self
            .command
            .take()
            .expect("command was None at start of WebSocket.");

        // Start PTY
        self.cons = Some(Terminal::new(ctx.address(), command).start());
        trace!("Started WebSocket");
    }

    fn stopping(&mut self, ctx: &mut Self::Context) -> Running {
        trace!("Stopping WebSocket");

        Running::Stop
    }

    fn stopped(&mut self, ctx: &mut Self::Context) {
        trace!("Stopped WebSocket");
    }
}

impl Handler<event::IO> for TermSocket {
    type Result = ();

    fn handle(&mut self, msg: event::IO, ctx: &mut <Self as Actor>::Context) {
        trace!("Websocket <- Terminal : {:?}", msg);
        // println!("msg: {}", String::from_utf8_lossy(msg.as_ref()));
        // ctx.text(String::from_utf8_lossy(msg.as_ref()));
        ctx.binary(msg);
    }
}

impl Handler<event::TerminadoMessage> for TermSocket {
    type Result = ();

    fn handle(&mut self, msg: event::TerminadoMessage, ctx: &mut <Self as Actor>::Context) {
        trace!("Websocket <- Terminal : {:?}", msg);
        match msg {
            event::TerminadoMessage::Stdout(_) => {
                let json = serde_json::to_string(&msg);

                if let Ok(json) = json {
                    ctx.text(json);
                }
            }
            _ => error!(r#"Invalid event::TerminadoMessage to Websocket: only "stdout" supported"#),
        }
    }
}

pub struct Terminal {
    pty_write: Option<AsyncPtyMasterWriteHalf>,
    child: Option<Child>,
    ws: Addr<TermSocket>,
    command: Command,
}

impl Terminal {
    pub fn new(ws: Addr<TermSocket>, command: Command) -> Self {
        Self {
            pty_write: None,
            child: None,
            ws,
            command,
        }
    }
}

impl Actor for Terminal {
    type Context = Context<Self>;

    fn started(&mut self, ctx: &mut Context<Self>) {
        info!("Started Terminal");
        let pty = match AsyncPtyMaster::open() {
            Err(e) => {
                error!("Unable to open PTY: {:?}", e);
                ctx.stop();
                return;
            }
            Ok(pty) => pty,
        };

        let child = match self.command.spawn_pty_async(&pty) {
            Err(e) => {
                error!("Unable to spawn child: {:?}", e);
                ctx.stop();
                return;
            }
            Ok(child) => child,
        };

        info!("Spawned new child process with PID {}", child.id());

        let (pty_read, pty_write) = pty.split();

        self.pty_write = Some(pty_write);
        self.child = Some(child);

        let a = Framed::new(pty_read, BytesCodec);

        Self::add_stream(a, ctx);
    }

    fn stopping(&mut self, ctx: &mut Self::Context) -> Running {
        info!("Stopping Terminal");

        let child = self.child.take();

        if child.is_none() {
            // Great, child is already dead!
            return Running::Stop;
        }

        let mut child = child.unwrap();


        match child.kill() {
            Ok(()) => match child.wait() {
                Ok(exit) => info!("Child died: {:?}", exit),
                Err(e) => error!("Child wouldn't die: {}", e),
            },
            Err(e) => error!("Could not kill child with PID {}: {}", child.id(), e),
        };

        // Notify the websocket that the child died.
        self.ws.do_send(event::ChildDied());

        Running::Stop
    }

    fn stopped(&mut self, ctx: &mut Self::Context) {
        info!("Stopped Terminal");
    }
}

impl StreamHandler<<BytesCodec as Decoder>::Item> for Terminal {
    fn handle(&mut self, msg: <BytesCodec as Decoder>::Item, _ctx: &mut Self::Context) {
        self.ws
            .do_send(event::TerminadoMessage::Stdout(event::IO(msg)));
    }
}


impl Handler<event::IO> for Terminal {
    type Result = ();

    fn handle(&mut self, item: event::IO, ctx: &mut Self::Context) {
        let pty = match self.pty_write {
            Some(ref mut p) => p,
            None => {
                error!("Write half of PTY died, stopping Terminal.");
                ctx.stop();
                return;
            }
        };

        if let Err(e) = pty.write(item.as_ref()) {
            error!("Could not write to PTY: {}", e);
            ctx.stop();
        }

        trace!("Websocket -> Terminal : {:?}", item);
    }
}

impl Handler<event::TerminadoMessage> for Terminal {
    type Result = ();

    fn handle(&mut self, msg: event::TerminadoMessage, ctx: &mut <Self as Actor>::Context) {
        let pty = match self.pty_write {
            Some(ref mut p) => p,
            None => {
                error!("Write half of PTY died, stopping Terminal.");
                ctx.stop();
                return;
            }
        };

        trace!("Websocket -> Terminal : {:?}", msg);
        match msg {
            event::TerminadoMessage::Stdin(io) => {
                if let Err(e) = pty.write(io.as_ref()) {
                    error!("Could not write to PTY: {}", e);
                    ctx.stop();
                }
            }
            event::TerminadoMessage::Resize { rows, cols } => {
                info!("Resize: cols = {}, rows = {}", cols, rows);
                if let Err(e) = event::Resize::new(pty, rows, cols).wait() {
                    error!("Resize failed: {}", e);
                    ctx.stop();
                }
            }
            event::TerminadoMessage::Stdout(_) => {
                error!("Invalid Terminado Message: Stdin cannot go to PTY")
            }
        };
    }
}

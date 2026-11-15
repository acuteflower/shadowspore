//! Persistent Nakama Realtime WebSocket client for live presence and coop notifications.

use std::sync::Mutex;
use std::time::Duration;

use futures_util::{SinkExt, StreamExt};
use serde::Serialize;
use serde_json::{json, Value};
use tauri::async_runtime::JoinHandle;
use tauri::{AppHandle, Emitter};
use tokio_tungstenite::{connect_async, tungstenite::Message};

use crate::nakama;

#[derive(Debug, Clone, Serialize)]
pub struct WsStatusPayload {
    pub connected: bool,
    pub server_url: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct WsPresencePayload {
    pub joins: usize,
    pub leaves: usize,
}

pub struct WsController {
    task: Mutex<Option<JoinHandle<()>>>,
}

impl WsController {
    pub fn new() -> Self {
        Self {
            task: Mutex::new(None),
        }
    }

    pub fn disconnect(&self, app: &AppHandle, server_url: &str) {
        if let Some(handle) = self.task.lock().unwrap().take() {
            handle.abort();
        }
        let _ = app.emit(
            "coop://ws-status",
            WsStatusPayload {
                connected: false,
                server_url: server_url.to_string(),
            },
        );
    }

    pub fn connect(&self, app: AppHandle, server_url: String, token: String) {
        if let Some(handle) = self.task.lock().unwrap().take() {
            handle.abort();
        }
        if token.trim().is_empty() || server_url.trim().is_empty() {
            let _ = app.emit(
                "coop://ws-status",
                WsStatusPayload {
                    connected: false,
                    server_url,
                },
            );
            return;
        }
        let handle = tauri::async_runtime::spawn(run_ws_loop(app, server_url, token));
        *self.task.lock().unwrap() = Some(handle);
    }
}

pub fn build_ws_url(server_url: &str, token: &str) -> String {
    let base = server_url.trim().trim_end_matches('/');
    let ws_base = if let Some(rest) = base.strip_prefix("https://") {
        format!("wss://{}", rest)
    } else if let Some(rest) = base.strip_prefix("http://") {
        format!("ws://{}", rest)
    } else {
        format!("ws://{}", base)
    };
    format!(
        "{}/ws?lang=en&status=true&format=json&token={}",
        ws_base,
        percent_encode(token.trim())
    )
}

fn percent_encode(input: &str) -> String {
    let mut out = String::with_capacity(input.len());
    for b in input.as_bytes() {
        match b {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => {
                out.push(*b as char);
            }
            _ => {
                out.push('%');
                out.push_str(&format!("{:02X}", b));
            }
        }
    }
    out
}

async fn run_ws_loop(app: AppHandle, server_url: String, token: String) {
    let ws_url = build_ws_url(&server_url, &token);
    let mut backoff_secs: u64 = 2;

    loop {
        match connect_async(&ws_url).await {
            Ok((stream, _)) => {
                backoff_secs = 2;
                let _ = app.emit(
                    "coop://ws-status",
                    WsStatusPayload {
                        connected: true,
                        server_url: server_url.clone(),
                    },
                );

                let (mut write, mut read) = stream.split();
                // Publish an initial presence status message so friends immediately see us online.
                let status_msg = json!({ "status_update": { "status": "Im Launcher" } }).to_string();
                let _ = write.send(Message::Text(status_msg.into())).await;

                let mut ping_interval = tokio::time::interval(Duration::from_secs(25));
                ping_interval.tick().await;

                loop {
                    tokio::select! {
                        _ = ping_interval.tick() => {
                            if write.send(Message::Ping(Vec::new().into())).await.is_err() {
                                break;
                            }
                        }
                        frame = read.next() => {
                            match frame {
                                Some(Ok(Message::Text(text))) => {
                                    handle_rt_frame(&app, &text);
                                }
                                Some(Ok(Message::Ping(data))) => {
                                    if write.send(Message::Pong(data)).await.is_err() {
                                        break;
                                    }
                                }
                                Some(Ok(Message::Close(_))) | Some(Err(_)) | None => {
                                    break;
                                }
                                _ => {}
                            }
                        }
                    }
                }
            }
            Err(_) => {}
        }

        let _ = app.emit(
            "coop://ws-status",
            WsStatusPayload {
                connected: false,
                server_url: server_url.clone(),
            },
        );
        tokio::time::sleep(Duration::from_secs(backoff_secs)).await;
        backoff_secs = (backoff_secs * 2).min(15);
    }
}

fn handle_rt_frame(app: &AppHandle, raw: &str) {
    let Ok(val) = serde_json::from_str::<Value>(raw) else {
        return;
    };

    if let Some(items) = val
        .get("notifications")
        .and_then(|n| n.get("notifications"))
        .and_then(|arr| arr.as_array())
    {
        for item in items {
            if let Some(parsed) = nakama::parse_notification_json(item) {
                let _ = app.emit("coop://notification", parsed);
            }
        }
    }

    if let Some(pres) = val.get("status_presence_event") {
        let joins = pres
            .get("joins")
            .and_then(|v| v.as_array())
            .map(|a| a.len())
            .unwrap_or(0);
        let leaves = pres
            .get("leaves")
            .and_then(|v| v.as_array())
            .map(|a| a.len())
            .unwrap_or(0);
        if joins > 0 || leaves > 0 {
            let _ = app.emit("coop://presence", WsPresencePayload { joins, leaves });
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn converts_http_and_https_to_ws_urls() {
        assert_eq!(
            build_ws_url("http://127.0.0.1:7350/", "tok.en+1"),
            "ws://127.0.0.1:7350/ws?lang=en&status=true&format=json&token=tok.en%2B1"
        );
        assert_eq!(
            build_ws_url("https://s.shadowspore.com", "abc"),
            "wss://s.shadowspore.com/ws?lang=en&status=true&format=json&token=abc"
        );
    }
}

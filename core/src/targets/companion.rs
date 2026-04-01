use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::{mpsc, oneshot};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CompanionDevice {
    pub device_id: String,
    pub device_name: String,
    pub platform: String,
    pub connected_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type")]
pub enum CompanionMessage {
    // Desktop → Companion
    #[serde(rename = "screenshot")]
    ScreenshotRequest,
    #[serde(rename = "start_recording")]
    StartRecording { fps: u32 },
    #[serde(rename = "stop_recording")]
    StopRecording,
    #[serde(rename = "ping")]
    Ping,

    // Companion → Desktop
    #[serde(rename = "frame")]
    Frame { data: String, timestamp: u64 },
    #[serde(rename = "screenshot_result")]
    ScreenshotResult { data: String },
    #[serde(rename = "recording_stopped")]
    RecordingStopped,
    #[serde(rename = "pong")]
    Pong {
        device_name: String,
        device_id: String,
    },
}

pub enum CompanionCommand {
    Screenshot {
        reply: oneshot::Sender<Result<Vec<u8>, String>>,
    },
}

pub struct CompanionManager {
    devices: HashMap<String, CompanionDevice>,
    connections: HashMap<String, Vec<(String, mpsc::Sender<CompanionCommand>)>>,
    latest_frames: HashMap<String, (Vec<u8>, std::time::Instant)>,
    listener_port: u16,
}

impl CompanionManager {
    pub fn new() -> Self {
        CompanionManager {
            devices: HashMap::new(),
            connections: HashMap::new(),
            latest_frames: HashMap::new(),
            listener_port: 0,
        }
    }

    pub fn list_devices(&self) -> Vec<CompanionDevice> {
        self.devices.values().cloned().collect()
    }

    pub fn get_device(&self, device_id: &str) -> Option<&CompanionDevice> {
        self.devices.get(device_id)
    }

    pub fn add_device(&mut self, device: CompanionDevice) {
        tracing::info!(
            "Companion device connected: {} ({})",
            device.device_name,
            device.device_id
        );
        self.devices.insert(device.device_id.clone(), device);
    }

    pub fn remove_device(&mut self, device_id: &str) {
        if let Some(device) = self.devices.remove(device_id) {
            tracing::info!("Companion device disconnected: {}", device.device_name);
        }
    }

    pub fn register_connection(
        &mut self,
        device_id: &str,
        conn_id: &str,
        sender: mpsc::Sender<CompanionCommand>,
    ) {
        self.connections
            .entry(device_id.to_string())
            .or_default()
            .push((conn_id.to_string(), sender));
        tracing::debug!(
            "Registered connection {} for device {}",
            conn_id,
            device_id
        );
    }

    pub fn unregister_connection(&mut self, device_id: &str, conn_id: &str) {
        if let Some(conns) = self.connections.get_mut(device_id) {
            conns.retain(|(id, _)| id != conn_id);
            if conns.is_empty() {
                self.connections.remove(device_id);
                self.latest_frames.remove(device_id);
                self.remove_device(device_id);
            }
        }
    }

    pub fn store_frame(&mut self, device_id: &str, jpeg_bytes: Vec<u8>) {
        self.latest_frames
            .insert(device_id.to_string(), (jpeg_bytes, std::time::Instant::now()));
    }

    /// Returns the latest frame only if it's less than 500ms old (broadcast actively sending).
    pub fn get_latest_frame(&self, device_id: &str) -> Option<&Vec<u8>> {
        self.latest_frames.get(device_id).and_then(|(bytes, ts)| {
            if ts.elapsed() < std::time::Duration::from_millis(500) {
                Some(bytes)
            } else {
                None
            }
        })
    }

    pub fn get_senders(&self, device_id: &str) -> Vec<mpsc::Sender<CompanionCommand>> {
        self.connections
            .get(device_id)
            .map(|conns| conns.iter().map(|(_, s)| s.clone()).collect())
            .unwrap_or_default()
    }

    /// Start the WebSocket listener for companion devices.
    /// Also registers the mDNS service for Bonjour discovery.
    pub async fn start_listener(&mut self) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
        use tokio::net::TcpListener;

        // Use fixed port 58000 so iOS devices can reconnect after sleep/restart.
        // Fall back to random port if 58000 is busy.
        let listener = match TcpListener::bind("0.0.0.0:58000").await {
            Ok(l) => l,
            Err(_) => TcpListener::bind("0.0.0.0:0").await?,
        };
        let port = listener.local_addr()?.port();
        self.listener_port = port;

        tracing::info!("Companion WebSocket listener on port {}", port);

        // Register mDNS service for Bonjour discovery
        if let Err(e) = register_mdns_service(port) {
            tracing::warn!("Failed to register mDNS service: {}", e);
        }

        // Accept WebSocket connections
        tokio::spawn(async move {
            loop {
                match listener.accept().await {
                    Ok((stream, addr)) => {
                        tracing::info!("Companion connection from {}", addr);
                        let peer_ip = addr.ip();
                        tokio::spawn(handle_companion_connection(stream, peer_ip));
                    }
                    Err(e) => {
                        tracing::error!("Failed to accept companion connection: {}", e);
                    }
                }
            }
        });

        Ok(())
    }
}

/// Stored dns-sd child process so it gets killed on drop (app exit) — macOS only
static MDNS_CHILD: parking_lot::Mutex<Option<std::process::Child>> = parking_lot::Mutex::new(None);

/// Stored mdns-sd daemon so it stays alive — Windows/Linux
static MDNS_DAEMON: parking_lot::Mutex<Option<mdns_sd::ServiceDaemon>> = parking_lot::Mutex::new(None);

fn register_mdns_service(port: u16) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    let full_hostname = gethostname::gethostname()
        .to_string_lossy()
        .into_owned();
    let short_name = full_hostname
        .split('.')
        .next()
        .unwrap_or(&full_hostname)
        .to_string();

    // On macOS, use the system dns-sd command to avoid conflicts with mDNSResponder.
    // On Windows/Linux, use the mdns-sd crate directly.
    if cfg!(target_os = "macos") {
        register_mdns_via_dnssd(&short_name, port)
    } else {
        register_mdns_via_crate(&short_name, port)
    }
}

fn register_mdns_via_dnssd(name: &str, port: u16) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    if let Some(mut prev) = MDNS_CHILD.lock().take() {
        let _ = prev.kill();
    }

    let child = std::process::Command::new("dns-sd")
        .args(["-R", name, "_screenshottool._tcp", "local", &port.to_string()])
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .spawn()?;

    *MDNS_CHILD.lock() = Some(child);
    tracing::info!("Registered mDNS service: {} on port {} (via system dns-sd)", name, port);
    Ok(())
}

fn register_mdns_via_crate(name: &str, port: u16) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    let daemon = mdns_sd::ServiceDaemon::new()?;

    let service_type = "_screenshottool._tcp.local.";
    let host_name = &format!("{}.local.", name);

    let mut properties = HashMap::new();
    properties.insert("version".to_string(), "1".to_string());

    // Get the local IPv4 address explicitly since auto-detect may fail on Windows
    let local_ip = get_local_ipv4().unwrap_or_else(|| "0.0.0.0".to_string());
    tracing::info!("mDNS: using local IP {} for service registration", local_ip);

    let service_info = mdns_sd::ServiceInfo::new(
        service_type,
        name,
        host_name,
        local_ip.as_str(),
        port,
        Some(properties),
    )?;

    daemon.register(service_info)?;

    tracing::info!("Registered mDNS service: {} on port {} at {} (via mdns-sd crate)", name, port, local_ip);

    // Keep daemon alive for the lifetime of the app
    *MDNS_DAEMON.lock() = Some(daemon);
    Ok(())
}

fn get_local_ipv4() -> Option<String> {
    // Find the first non-loopback IPv4 address
    if_addrs::get_if_addrs()
        .ok()?
        .into_iter()
        .filter(|iface| !iface.is_loopback())
        .find_map(|iface| match iface.addr {
            if_addrs::IfAddr::V4(v4) => Some(v4.ip.to_string()),
            _ => None,
        })
}

async fn handle_companion_connection(stream: tokio::net::TcpStream, _peer_ip: std::net::IpAddr) {
    use futures_util::{SinkExt, StreamExt};
    use tokio_tungstenite::tungstenite::Message;

    let ws_stream = match tokio_tungstenite::accept_async(stream).await {
        Ok(ws) => ws,
        Err(e) => {
            tracing::error!("WebSocket handshake failed: {}", e);
            return;
        }
    };

    let (mut write, mut read) = ws_stream.split();

    // Send ping to identify device
    let ping_msg = serde_json::to_string(&CompanionMessage::Ping).unwrap();
    if let Err(e) = write.send(Message::Text(ping_msg)).await {
        tracing::error!("Failed to send ping: {}", e);
        return;
    }

    // Wait for pong to identify the device
    let (device_id, device_name) = loop {
        match read.next().await {
            Some(Ok(Message::Text(text))) => {
                if let Ok(CompanionMessage::Pong {
                    device_name,
                    device_id,
                }) = serde_json::from_str(&text)
                {
                    break (device_id, device_name);
                }
            }
            Some(Err(e)) => {
                tracing::error!("Error waiting for pong: {}", e);
                return;
            }
            None => {
                tracing::info!("Connection closed before pong");
                return;
            }
            _ => {}
        }
    };

    tracing::info!("Device identified: {} ({})", device_name, device_id);

    // Register device and command channel
    let conn_id = uuid::Uuid::new_v4().to_string();
    let (cmd_tx, mut cmd_rx) = mpsc::channel::<CompanionCommand>(16);

    if let Some(state) = crate::get_state() {
        let mut mgr = state.companion_manager.write();
        mgr.add_device(CompanionDevice {
            device_id: device_id.clone(),
            device_name: device_name.clone(),
            platform: "unknown".to_string(),
            connected_at: chrono::Utc::now().to_rfc3339(),
        });
        mgr.register_connection(&device_id, &conn_id, cmd_tx);
    }

    // Pending screenshot reply — only one at a time per connection
    let mut pending_screenshot: Option<oneshot::Sender<Result<Vec<u8>, String>>> = None;
    let mut ping_interval = tokio::time::interval(std::time::Duration::from_secs(30));
    ping_interval.tick().await; // consume immediate first tick

    loop {
        tokio::select! {
            msg = read.next() => {
                match msg {
                    Some(Ok(Message::Text(text))) => {
                        match serde_json::from_str::<CompanionMessage>(&text) {
                            Ok(CompanionMessage::Pong { .. }) => {
                                // keepalive pong, ignore
                            }
                            Ok(CompanionMessage::Frame { data, timestamp: _ }) => {
                                if let Ok(jpeg_bytes) = base64::Engine::decode(
                                    &base64::engine::general_purpose::STANDARD,
                                    &data,
                                ) {
                                    if let Some(state) = crate::get_state() {
                                        state.companion_manager.write().store_frame(&device_id, jpeg_bytes);
                                    }
                                }
                            }
                            Ok(CompanionMessage::ScreenshotResult { data }) => {
                                match base64::Engine::decode(
                                    &base64::engine::general_purpose::STANDARD,
                                    &data,
                                ) {
                                    Ok(png_bytes) => {
                                        tracing::info!(
                                            "Received screenshot from companion: {} bytes",
                                            png_bytes.len()
                                        );
                                        if let Some(reply) = pending_screenshot.take() {
                                            let _ = reply.send(Ok(png_bytes));
                                        }
                                    }
                                    Err(e) => {
                                        tracing::warn!("Failed to decode screenshot data: {}", e);
                                        if let Some(reply) = pending_screenshot.take() {
                                            let _ = reply.send(Err(format!("decode error: {}", e)));
                                        }
                                    }
                                }
                            }
                            Ok(CompanionMessage::RecordingStopped) => {
                                tracing::info!("Companion stopped recording");
                            }
                            Ok(_) => {}
                            Err(e) => {
                                tracing::warn!("Invalid companion message: {}", e);
                            }
                        }
                    }
                    Some(Ok(Message::Close(_))) | None => {
                        tracing::info!("Companion {} disconnected", device_name);
                        break;
                    }
                    Some(Err(e)) => {
                        tracing::error!("Companion WebSocket error: {}", e);
                        break;
                    }
                    _ => {}
                }
            }
            cmd = cmd_rx.recv() => {
                match cmd {
                    Some(CompanionCommand::Screenshot { reply }) => {
                        let msg = serde_json::to_string(&CompanionMessage::ScreenshotRequest).unwrap();
                        if let Err(e) = write.send(Message::Text(msg)).await {
                            tracing::error!("Failed to send screenshot request: {}", e);
                            let _ = reply.send(Err(format!("send error: {}", e)));
                        } else {
                            pending_screenshot = Some(reply);
                        }
                    }
                    None => {
                        // Command channel closed
                        break;
                    }
                }
            }
            _ = ping_interval.tick() => {
                let ping_msg = serde_json::to_string(&CompanionMessage::Ping).unwrap();
                if let Err(e) = write.send(Message::Text(ping_msg)).await {
                    tracing::error!("Failed to send keepalive ping: {}", e);
                    break;
                }
            }
        }
    }

    // Cleanup
    if let Some(state) = crate::get_state() {
        state
            .companion_manager
            .write()
            .unregister_connection(&device_id, &conn_id);
    }
}

/// Request a screenshot from a companion device.
/// Sends the command to all connections for the device and returns the first successful result.
pub async fn request_companion_screenshot(
    manager: &parking_lot::RwLock<CompanionManager>,
    device_id: &str,
) -> Result<Vec<u8>, String> {
    let senders = {
        let mgr = manager.read();
        mgr.get_senders(device_id)
    };

    if senders.is_empty() {
        return Err(format!("No connections for device {}", device_id));
    }

    // Use a shared slot for first-response-wins
    let result_tx = Arc::new(tokio::sync::Mutex::new(
        None::<oneshot::Sender<Result<Vec<u8>, String>>>,
    ));
    let (final_tx, final_rx) = oneshot::channel::<Result<Vec<u8>, String>>();
    {
        let mut slot = result_tx.lock().await;
        *slot = Some(final_tx);
    }

    for sender in senders {
        let (reply_tx, reply_rx) = oneshot::channel();
        let result_tx = result_tx.clone();

        if sender
            .send(CompanionCommand::Screenshot { reply: reply_tx })
            .await
            .is_err()
        {
            continue;
        }

        tokio::spawn(async move {
            if let Ok(result) = reply_rx.await {
                let mut slot = result_tx.lock().await;
                if let Some(tx) = slot.take() {
                    let _ = tx.send(result);
                }
            }
        });
    }

    match tokio::time::timeout(std::time::Duration::from_secs(10), final_rx).await {
        Ok(Ok(result)) => result,
        Ok(Err(_)) => Err("All connections dropped without responding".to_string()),
        Err(_) => Err("Screenshot request timed out (10s)".to_string()),
    }
}

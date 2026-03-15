use serde::{Deserialize, Serialize};
use std::collections::HashMap;

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

pub struct CompanionManager {
    devices: HashMap<String, CompanionDevice>,
    listener_port: u16,
}

impl CompanionManager {
    pub fn new() -> Self {
        CompanionManager {
            devices: HashMap::new(),
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

    /// Start the WebSocket listener for companion devices.
    /// Also registers the mDNS service for Bonjour discovery.
    pub async fn start_listener(&mut self) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
        use tokio::net::TcpListener;

        let listener = TcpListener::bind("0.0.0.0:0").await?;
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
                        tokio::spawn(handle_companion_connection(stream));
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

fn register_mdns_service(port: u16) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    let mdns = mdns_sd::ServiceDaemon::new()?;
    let service_type = "_screenshottool._tcp.local.";
    let instance_name = gethostname::gethostname()
        .to_string_lossy()
        .into_owned();

    let service_info = mdns_sd::ServiceInfo::new(
        service_type,
        &instance_name,
        &format!("{}.", instance_name),
        "",
        port,
        None,
    )?;

    mdns.register(service_info)?;
    tracing::info!("Registered mDNS service: {}", instance_name);

    // Keep mdns alive — it will be dropped when the process exits
    std::mem::forget(mdns);

    Ok(())
}

async fn handle_companion_connection(stream: tokio::net::TcpStream) {
    use futures_util::{SinkExt, StreamExt};

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
    if let Err(e) = write
        .send(tokio_tungstenite::tungstenite::Message::Text(ping_msg))
        .await
    {
        tracing::error!("Failed to send ping: {}", e);
        return;
    }

    while let Some(msg) = read.next().await {
        match msg {
            Ok(tokio_tungstenite::tungstenite::Message::Text(text)) => {
                match serde_json::from_str::<CompanionMessage>(&text) {
                    Ok(CompanionMessage::Pong {
                        device_name,
                        device_id,
                    }) => {
                        tracing::info!("Device identified: {} ({})", device_name, device_id);
                        if let Some(state) = crate::get_state() {
                            state.companion_manager.write().add_device(CompanionDevice {
                                device_id: device_id.clone(),
                                device_name,
                                platform: "unknown".to_string(),
                                connected_at: chrono::Utc::now().to_rfc3339(),
                            });
                        }
                    }
                    Ok(CompanionMessage::Frame { data, timestamp: _ }) => {
                        // Decode base64 JPEG frame from companion
                        if let Ok(jpeg_bytes) = base64::Engine::decode(
                            &base64::engine::general_purpose::STANDARD,
                            &data,
                        ) {
                            tracing::debug!(
                                "Received frame from companion: {} bytes",
                                jpeg_bytes.len()
                            );
                            // Process frame through image pipeline
                            // This could be fed into a GIF session or returned as screenshot
                        }
                    }
                    Ok(CompanionMessage::ScreenshotResult { data }) => {
                        if let Ok(png_bytes) = base64::Engine::decode(
                            &base64::engine::general_purpose::STANDARD,
                            &data,
                        ) {
                            tracing::debug!(
                                "Received screenshot from companion: {} bytes",
                                png_bytes.len()
                            );
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
            Ok(tokio_tungstenite::tungstenite::Message::Close(_)) => {
                tracing::info!("Companion disconnected");
                break;
            }
            Err(e) => {
                tracing::error!("Companion WebSocket error: {}", e);
                break;
            }
            _ => {}
        }
    }
}

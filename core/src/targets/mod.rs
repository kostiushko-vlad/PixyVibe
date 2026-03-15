pub mod companion;

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum Target {
    Desktop,
    Companion {
        device_id: String,
        device_name: String,
    },
}

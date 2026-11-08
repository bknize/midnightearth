class_name NetDefaults
extends RefCounted
## The PVP client's compiled-in defaults (cycle 12 plan P10, P16; spec R15, R45, R51).
## Constants only.

## The match server's port: next to the trainer MCP's 8765, a different process.
const PORT: int = 8766
## The PC's LAN address (plan P16). Ben changes it to the public address before an export
## for friends, or they type it into the title screen's server field.
const SERVER_HOST: String = "192.168.68.63"
## SERVER_HOST:PORT, the form the server field and `--server=` take.
const SERVER_ADDRESS: String = "192.168.68.63:8766"
## How long a connection attempt may take before it counts as unreachable (R15).
const CONNECT_TIMEOUT_MS: int = 10000
## After a drop mid-match, a reconnect is tried this often (R45)...
const RETRY_MS: int = 3000
## ...for this long after the drop, then the client gives up (R51). The server keeps the
## room as long (its RECONNECT_WINDOW_MS).
const RECONNECT_WINDOW_MS: int = 120000

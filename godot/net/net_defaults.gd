class_name NetDefaults
extends RefCounted
## The PVP client's compiled-in defaults (cycle 12 plan P10, P16; spec R15, R45, R51).
## Constants only.

## The PC's LAN address and the match server's port (plan P16; port 8766, next to the
## trainer MCP's 8765, a different process), the form the server field and `--server=`
## take. Ben changes it to the public address before an export for friends, or they type
## it into the title screen's server field.
const SERVER_ADDRESS: String = "192.168.68.63:8766"
## How long a connection attempt may take before it counts as unreachable (R15).
const CONNECT_TIMEOUT_MS: int = 10000
## After a drop mid-match, a reconnect is tried this often (R45)...
const RETRY_MS: int = 3000
## ...for this long after the drop, then the client gives up (R51). The server keeps the
## room as long (MatchRoom.RECONNECT_WINDOW_MS is this value).
const RECONNECT_WINDOW_MS: int = 120000
## An open connection with nothing sent for this long sends `ping`; the server answers
## `pong`, so a live connection never goes this long without traffic either way.
const PING_MS: int = 5000
## An open connection that has received nothing for this long is taken as lost (a peer gone
## without a TCP close: sleep, Wi-Fi loss) and reported as a drop. Three missed pings.
const RECEIVE_TIMEOUT_MS: int = 15000
## WebSocketPeer.heartbeat_interval (seconds): protocol-level ping frames under the
## application's own `ping`, which also keep NAT mappings alive.
const HEARTBEAT_S: float = 5.0

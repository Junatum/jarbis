# Security baseline

- Disabled by default. No automatic broker, firewall rule or WAN listener creation.
- Read and write RPCs have distinct ACL methods. Do not bind `jarbis` to unauthenticated ACLs.
- Runtime command checks device membership in UCI and refuses all but `light_set` power/brightness; no arbitrary MQTT publish, command, shell or topic input via RPC.
- Per-device Tasmota topic is restricted to ASCII alphanumeric, `_`, and `-`; wildcard `+`, `#` and `/` are prohibited.
- No secrets are returned by `status` or `devices_list`.
- MQTT credentials belong in `/etc/jarbis/mosquitto_pub` (mode 0600) and are loaded through the 2.0-compatible `XDG_CONFIG_HOME` file mechanism; they must **not** be passed with `-P` in the process arguments.
- For external brokers, use an isolated IoT network and authenticated ACLs. The initial nossl transport is suitable only where trusted network isolation provides acceptable protection; TLS-capable clients must be evaluated for deployments needing encryption in transit.
- MQTT messages use QoS 1 without retain; client success indicates broker acknowledgement only, not physical state.
- Do not expose or forward port 1883 to WAN. Configure MQTT broker listener/credentials/ACLs explicitly, including for Tasmota devices.
- Future AI or automation must not bypass authenticated control and must apply policy controls before executing actions.

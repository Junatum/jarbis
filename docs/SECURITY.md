# Security baseline

- Disabled by default. On explicit enable/start, managed Broker config creates 127.0.0.1 and LAN-IP listeners with authentication, not WAN or firewall rules. Existing custom Mosquitto configuration is refused rather than modified.
- Read and write RPCs have distinct ACL methods. Do not bind `jarbis` to unauthenticated ACLs.
- Runtime command checks device membership in UCI and refuses all but `light_set` power/brightness; no arbitrary MQTT publish, command, shell or topic input via RPC.
- Per-device Tasmota topic is restricted to ASCII alphanumeric, `_`, and `-`; wildcard `+`, `#` and `/` are prohibited.
- No secrets are returned by `status` or `devices_list`.
- MQTT credentials belong in `/etc/jarbis/mosquitto_pub` (mode 0600) and are loaded through the 2.0-compatible `XDG_CONFIG_HOME` file mechanism; they must **not** be passed with `-P` in the process arguments.
- For external brokers, use an isolated IoT network and authenticated ACLs. The initial nossl transport is suitable only where trusted network isolation provides acceptable protection; TLS-capable clients must be evaluated for deployments needing encryption in transit.
- MQTT messages use QoS 1 without retain; client success indicates broker acknowledgement only, not physical state.
- Do not expose or forward port 1883 to WAN. The managed MQTT Broker uses one shared randomly generated user and defaults to allow_anonymous=0; shared credentials are an initial-test limitation. For deployment hardening add per-device MQTT users and topic ACLs. No unauthenticated WAN listener is created.
- Future AI or automation must not bypass authenticated control and must apply policy controls before executing actions.

- The firmware image must never contain an MQTT credential file. Config backups and sysupgrade backups containing `/etc/jarbis/mosquitto_pub` must be treated as sensitive archives and protected accordingly.
- A post-install rpcd restart is only attempted if reload fails to restore the `jarbis` RPC object; it is not an always-on service or recurring retry loop.

## Discovery trust boundary

- `discovery_scan` requires write ACL; `discovery_list` requires read ACL. Discovery is **read-only to devices**: it never changes Tasmota configuration, installs credentials, or adds UCI devices.
- IPv4 HTTP probes use only DHCP leases matching a configured static `/24` LAN, maximum 8 devices with 2s timeout and 4KiB output cap. MQTT discovery has a 2s/32KiB bounded retained-message window. Untrusted names/topics are validated before inclusion; no shell interpolation of MQTT payload is performed.
- Discovery cache is `/tmp` only, with mode 0600 and bounded size; information is not uploaded. Results are advisory, not trusted authorization for `light_set`.
- The managed MQTT broker requires the `mosquitto_passwd` hash utility. If absent or an existing custom configuration is detected, it **fails closed**. Never put passwords in CLI arguments or a firmware image. A temporary plaintext password file is briefly kept in `/tmp` during the one-time hashing step.

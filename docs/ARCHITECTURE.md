# Architecture (0.1.0-r1)

```
SmartSafeHub LuCI (future integration)
       │ authenticated ubus
       ▼
rpcd ucode object 'jarbis'
       │
       ├─ read-only: status, devices_list  ─→ UCI configuration
       │
       └─ write: light_set
                 └─ jarbis-control (input + UCI membership validation)
                         └─ mosquitto_pub
                                └─ MQTT broker ── Tasmota light
```

## API v1

- `status {}` → `{ok:true, data:{apiVersion:1, version, enabled, mqttConfigured, features}, error:null}`
- `devices_list {}` → `{ok:true, data:{devices:[{id,name,kind,protocol,enabled,capabilities}]},error:null}`
- `light_set {id,capability,value}` → `{ok:true,data:{accepted:true,id,capability,value},error:null}` (publish ACK, **not** lamp state)
- Failure → `{ok:false,data:null,error:{code,message}}`
- Capability: `power`: `ON|OFF`, `brightness`: decimal string `0..100`.

Only manually registered `config device` entries with `kind=light,protocol=tasmota,enabled=1` can be controlled. The Tasmota standard FullTopic `%prefix%/%topic%/` is assumed; custom FullTopic is not supported yet.

## Forward-compatible model (design only, not implemented)

```
Device ID (stable) + device kind
  └─ capabilities (power, brightness, color_temperature, color, ...)
    └─ state (observed, timestamp, source)
      └─ events (device, time, network, ...)
        └─ rules (trigger, conditions, actions)
          └─ policy check / Action Executor
            └─ adapter (Tasmota, Matter, ...)
```

- All automation actions must use the same constrained device control boundary.
- Separate observations from desired state. MQTT publish success does not imply a state change.
- AI proposes actions but must pass policy/authorization checks and must be optional.
- Avoid new resident daemons, log-heavy polling or flash write loops until automated events require them.

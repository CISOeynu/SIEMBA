# Syslog Integration

SIEMBA listens for syslog on **UDP and TCP port 5514** out of the box.

## Configure in SIEMBA UI

1. Go to **Integrations** → click **Syslog**
2. Set Listen Host (default: `0.0.0.0` — all interfaces)
3. Set UDP Port (default: `5514`) and TCP Port (default: `5514`)
4. Click **Save Config** then **Test Connection**

## Sending Logs to SIEMBA

### Linux server (rsyslog)
```bash
echo "*.* @YOUR_SIEMBA_IP:5514" | sudo tee -a /etc/rsyslog.conf
sudo systemctl restart rsyslog
```

### Linux server (syslog-ng)
```
destination d_siemba { network("YOUR_SIEMBA_IP" port(5514) transport("udp")); };
log { source(s_src); destination(d_siemba); };
```

### Cisco IOS
```
logging host YOUR_SIEMBA_IP transport udp port 5514
logging trap informational
```

### Fortinet FortiGate
```
config log syslogd setting
  set status enable
  set server YOUR_SIEMBA_IP
  set port 5514
  set facility local7
end
```

### Palo Alto Networks
Go to **Device → Server Profiles → Syslog** → Add server: IP = your SIEMBA IP, Port = 5514, Transport = UDP.

### Windows (via NXLog)
```xml
<Output out>
  Module  om_udp
  Host    YOUR_SIEMBA_IP
  Port    5514
</Output>
```

## Viewing Syslog Data

- **SIEMBA Dashboard** → Alerts (filter Source = syslog)
- **Kibana** → Index pattern `siemba-syslog-*`
- **Grafana** → Syslog dashboard (provisioned automatically)

## Adding Custom Syslog Sources

You can add multiple named syslog sources via **Integrations → Syslog → Add Source**. Each source can be assigned a descriptive name (e.g. "Perimeter Firewall", "Core Switch") which appears as a tag in all events from that IP.

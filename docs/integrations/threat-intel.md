# Threat Intelligence Integration

SIEMBA matches all incoming events against your threat intelligence feeds in real time.

## How It Works

1. You upload IP lists, domain lists, or JSON feeds via the **Threat Intel** page
2. SIEMBA converts them to YAML lookup tables that Logstash reads
3. Every new event gets checked against all active feeds
4. Matches are tagged `ti_matched=true`, severity is escalated to `critical`, and the event is written to `siemba-ti-hits-*`
5. Threat intel hits appear on the **Dashboard** and in the **Alerts** view

## Adding a URL Feed

Go to **Threat Intel** → **Add URL** tab:
- **Name** — a label for this feed (e.g. "Emerging Threats IPs")
- **URL** — a direct link to a plain text file with one indicator per line
- **Type** — IP, Domain, URL, or File Hash

SIEMBA fetches the feed immediately and refreshes it on the configured interval.

**Example public feeds:**
```
https://rules.emergingthreats.net/blockrules/compromised-ips.txt
https://feodotracker.abuse.ch/downloads/ipblocklist.txt
https://raw.githubusercontent.com/stamparm/ipsum/master/ipsum.txt
```

## Uploading a File Feed

Go to **Threat Intel** → **Upload** tab. Supported formats:

**Plain text** (one indicator per line):
```
1.2.3.4
5.6.7.8
malicious-domain.com
```

**JSON array:**
```json
["1.2.3.4", "5.6.7.8", "malicious-domain.com"]
```

**JSON with indicators key:**
```json
{"indicators": [{"indicator": "1.2.3.4"}, {"indicator": "bad.com"}]}
```

**STIX2:**
```json
{"objects": [{"type": "indicator", "pattern": "[ipv4-addr:value = '1.2.3.4']"}]}
```

## IoC Lookup

Go to **Threat Intel** → **Lookup** tab. Enter any IP, domain, or URL to instantly check if it matches any loaded feed.

## Refreshing Feeds

Click **Refresh All URL Feeds** to re-fetch all URL-based feeds. This also happens automatically on the configured interval (default: every hour).

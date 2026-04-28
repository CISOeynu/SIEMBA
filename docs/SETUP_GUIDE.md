# SIEMBA Setup Guide — Step by Step

A complete walkthrough from a blank machine to a running SIEMBA instance. No prior Linux experience required.

---

## What You Need Before Starting

**Hardware:**
- 16 GB RAM minimum (32 GB recommended)
- 4 CPU cores (8 recommended)
- 100 GB free disk (SSD preferred)
- Internet access

**Supported OS:**
- Ubuntu 22.04 LTS or 24.04 LTS (recommended for production)
- macOS 13 Ventura or later (for local/dev use)

**Other requirements:**
- A domain name (e.g. `siemba.yourcompany.com`) — or use an IP address
- If using a domain: DNS access to point it at your server
- sudo / administrator access on the machine

---

## Ubuntu — Full Native Install

### Step 1 — Update your system

```bash
sudo apt update && sudo apt upgrade -y
```

### Step 2 — Run the installer

```bash
curl -fsSL https://raw.githubusercontent.com/YOUR_ORG/siemba/main/scripts/install.sh | sudo bash -s -- --mode=full
```

The installer will ask three questions:
- Your domain name (or press Enter to use the server's IP)
- Your admin email (used for the Let's Encrypt SSL certificate)
- Install type: Full native or Docker

**Installation takes 15–40 minutes** depending on internet speed.

### Step 3 — Save your credentials

At the end, the installer prints:
```
URL:      https://siemba.yourcompany.com
Username: admin
Password: xK9#mP2qR...
```
**Copy and save the password immediately** — it is shown only once.

### Step 4 — Open SIEMBA

Go to `https://your-domain-or-ip` in your browser. If you used a self-signed certificate, click **Advanced → Proceed**.

---

## Ubuntu / macOS — Docker Install

### Step 1 — Install Docker

**Ubuntu:**
```bash
curl -fsSL https://get.docker.com | sudo bash
sudo usermod -aG docker $USER && newgrp docker
```

**macOS:** Download Docker Desktop from https://docker.com and start it.

### Step 2 — Run the installer

```bash
curl -fsSL https://raw.githubusercontent.com/YOUR_ORG/siemba/main/scripts/install.sh | sudo bash -s -- --mode=docker
```

### Step 3 — Manage the stack

```bash
cd /opt/siemba
docker compose up -d          # start all
docker compose down           # stop all
docker compose logs -f        # live logs
docker compose restart kibana # restart one service
```

---

## First Login & Initial Setup

### 1. Log in
Go to your SIEMBA URL and log in with `admin` and the password from the installer.

### 2. Change your password
Click your username top-right → Settings → Password tab.

### 3. Add your first integration
Go to **Integrations** in the sidebar. Start with **Syslog** — it requires zero external credentials and immediately starts collecting logs from any device you point at it.

### 4. Configure alerting
Add Teams or Slack webhooks in Integrations so you get notified when critical events occur.

### 5. Upload threat intelligence
Go to **Threat Intel** → Upload a plain text file with one IP per line. SIEMBA immediately starts matching all incoming events against it.

---

## Syslog Quick Start

To send logs from any Linux server to SIEMBA:

```bash
# On the source server — edit rsyslog config
echo "*.* @YOUR_SIEMBA_IP:5514" | sudo tee -a /etc/rsyslog.conf
sudo systemctl restart rsyslog
```

For a Cisco/Fortinet/Palo Alto firewall, set the syslog server to your SIEMBA IP on port 5514 UDP.

---

## Updates

From SIEMBA: **Settings → System → Check for Updates**

Or from the command line:
```bash
sudo bash /opt/siemba/scripts/update.sh
```

---

## Backup

```bash
sudo bash /opt/siemba/scripts/backup.sh /your/backup/path
```

Backups are kept for 7 days automatically.

---

## Uninstall

```bash
sudo bash /opt/siemba/scripts/uninstall.sh
```

---

## Troubleshooting

**Services not starting:**
```bash
sudo systemctl status siemba-ui
sudo journalctl -u elasticsearch -n 50
```

**Elasticsearch out of memory:**
```bash
sudo nano /etc/elasticsearch/jvm.options.d/siemba.options
# Reduce from 4g to 2g
sudo systemctl restart elasticsearch
```

**Can't reach the web UI:**
```bash
sudo systemctl status nginx
sudo ufw status
sudo ufw allow 443/tcp
```

**Certificate errors:**
```bash
sudo certbot renew --force-renewal
sudo systemctl reload nginx
```

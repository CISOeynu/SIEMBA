# Microsoft Teams & Slack Alerts

SIEMBA sends alert notifications to Teams and/or Slack when an alert is escalated or when automatic severity thresholds are triggered.

---

## Microsoft Teams

### Step 1 — Create an Incoming Webhook

1. Open Microsoft Teams → go to the channel you want alerts in
2. Click **···** (More options) next to the channel → **Connectors**
3. Find **Incoming Webhook** → click **Configure**
4. Name: `SIEMBA Alerts`, upload the SIEMBA griffin logo (optional) → click **Create**
5. Copy the webhook URL — it looks like `https://yourcompany.webhook.office.com/webhookb2/...`

### Step 2 — Configure in SIEMBA

1. Go to **Integrations** → click **Microsoft Teams**
2. Paste the webhook URL
3. Set **Min Severity** (e.g. `high` — only high and critical alerts will be sent)
4. Click **Save Config** → **Test Connection**

A test message will appear in your Teams channel immediately.

---

## Slack

### Step 1 — Create a Slack App with Incoming Webhooks

1. Go to https://api.slack.com/apps → **Create New App** → **From scratch**
2. Name: `SIEMBA`, choose your workspace → click **Create App**
3. Click **Incoming Webhooks** → toggle **Activate Incoming Webhooks** ON
4. Click **Add New Webhook to Workspace** → choose your `#security-alerts` channel → **Allow**
5. Copy the webhook URL

### Step 2 — Configure in SIEMBA

1. Go to **Integrations** → click **Slack**
2. Fill in:
   - **Webhook URL** — from Step 1
   - **Default Channel** — e.g. `#security-alerts`
   - **Critical Channel** — e.g. `#security-critical` (critical alerts get routed here separately)
   - **Min Severity** — minimum severity to send (e.g. `high`)
3. Click **Save Config** → **Test Connection**

---

## Alert Format

**Teams alerts** use an Adaptive Card with color coding:
- 🔴 Critical — red
- 🟠 High — orange/warning

**Slack alerts** use emoji + bold severity prefix and route critical alerts to a separate channel automatically.

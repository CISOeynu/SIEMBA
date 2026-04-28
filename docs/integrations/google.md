# Google Workspace Integration

SIEMBA connects to Google Workspace using a Service Account with domain-wide delegation.

## Step 1 — Create a Google Cloud Project

1. Go to https://console.cloud.google.com
2. Create a new project or select an existing one
3. Go to **APIs & Services** → **Enable APIs** → search for and enable:
   - **Admin SDK API**
   - **Google Workspace Alert Center API** (optional)

## Step 2 — Create a Service Account

1. Go to **IAM & Admin** → **Service Accounts** → **Create Service Account**
2. Name: `siemba-reader` → click **Create and Continue**
3. Skip role assignment → click **Done**
4. Click your new service account → **Keys** → **Add Key** → **JSON**
5. Download the JSON key file — keep it safe

## Step 3 — Enable Domain-Wide Delegation

1. In the service account, click **Show Advanced Settings** → find the **Client ID** (a long number)
2. Go to your **Google Admin Console** (admin.google.com)
3. Go to **Security** → **Access and data control** → **API controls** → **Manage Domain Wide Delegation**
4. Click **Add new** → paste the Client ID
5. Add these OAuth scopes:
   ```
   https://www.googleapis.com/auth/admin.reports.audit.readonly
   https://www.googleapis.com/auth/admin.reports.usage.readonly
   ```
6. Click **Authorize**

## Step 4 — Configure in SIEMBA

1. Go to **Integrations** → click **Google Workspace**
2. Fill in:
   - **Workspace Domain** — your Google Workspace domain (e.g. `yourcompany.com`)
   - **Service Account JSON** — paste the entire contents of the downloaded JSON key file
   - **Poll Interval** — how often to fetch logs (default: 300 seconds)
3. Click **Save Config** → **Test Connection**

## What Gets Collected

- Admin activity (user creation, password resets, role changes)
- Login events (successful, failed, suspicious)
- Drive activity (sharing, deletion, external access)
- Google Workspace Security Center alerts

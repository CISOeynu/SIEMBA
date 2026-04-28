# Jira Integration

SIEMBA can automatically create Jira tickets when you escalate an alert.

## Step 1 — Create a Jira API Token

1. Go to https://id.atlassian.com/manage-profile/security/api-tokens
2. Click **Create API token**
3. Label: `SIEMBA` → click **Create**
4. Copy the token — it won't be shown again

## Step 2 — Configure in SIEMBA

1. Go to **Integrations** → click **Jira**
2. Fill in:
   - **Jira URL** — e.g. `https://yourcompany.atlassian.net`
   - **Email** — the Atlassian account email that owns the token
   - **API Token** — from Step 1
   - **Project Key** — the Jira project where tickets should be created (e.g. `SEC`)
   - **Issue Type** — e.g. `Task`, `Bug`, `Incident`
3. Click **Save Config** → **Test Connection**

## How Ticket Creation Works

When you click **ESCALATE** on any alert in SIEMBA:
- A Jira ticket is created in your configured project
- The summary includes the severity and a short message
- The full alert JSON is attached as the ticket description
- Priority is mapped automatically: critical → Highest, high → High, medium → Medium, low → Low

## Viewing Created Tickets

Created tickets appear in your Jira project. The Jira ticket key is returned to SIEMBA and logged with the alert.

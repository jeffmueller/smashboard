# Security policy

## Reporting a vulnerability

**Please don't open a public issue for a security problem.**

Use GitHub's private vulnerability reporting instead — the **Security** tab on
this repository, then **Report a vulnerability**. That opens a private thread
visible only to the maintainers.

Please include what you were able to do, the steps to reproduce it, and the
version or commit you were on. I'll acknowledge within a week.

## Why this matters more than usual here

smashboard is self-hosted, and an instance holds live credentials for the
accounts its owner has connected:

- OAuth refresh tokens for Google and Slack
- IMAP and CalDAV app passwords
- Home Assistant long-lived access tokens, and camera frames proxied through
  the server
- Anthropic Admin API keys
- API tokens minted for the app's own `/api/v1`

These are encrypted at rest with Active Record encryption and are never
rendered back to the browser after saving, but a flaw that reaches them reaches
somebody's mail and home. Anything touching credential storage, the OAuth
callbacks, the camera snapshot proxy, or `ApiToken` authentication is worth
reporting even if you're not sure it's exploitable.

## Scope

In scope: this application's code and its deployment scripts.

Out of scope: vulnerabilities in the third-party services smashboard connects
to — report those to the service. Also out of scope: findings that require an
attacker to already have the operator's server credentials or database access.

## Supported versions

This is a single-branch project. Fixes land on `main`; there are no backports
to older tags.

# Security & Production Hardening — tracked items

These are known gaps that must be closed before real users (not demo) rely on the system.
Not blockers for internal builds or controlled demos; blockers for production with real people's data.

## 1. Real KMS for the secrets store (HIGH — holds users' Abbott credentials)

**Status:** the durable secrets store (`KmsPostgresSecretsStore`, migration 012) is built and
correct, but on our VPS the only working KMS backend is `local` — which stores the master key
on the SAME VPS as the encrypted data. A full compromise of that box yields both ciphertext
and the key to decrypt it.

**Why it matters:** we store users' LibreLinkUp (Abbott) account passwords. Under India's DPDP
Act and basic security hygiene, third-party health-account credentials need a key isolated from
the data.

**Options (in order of preference):**
- Add a `CloudKmsClient` implementation (calls a managed KMS API over the network; the master
  key never lives on our VPS). The `KmsClient` abstraction already makes this a drop-in — only
  a new implementation, no call-site changes.
- Interim: keep `local` KMS but move the master key to a root-owned `600` file OUTSIDE the app
  directory and repo, injected at deploy. Better than an env var; still same-box.
- Long-term ideal: don't store the password at all — persist only Abbott's session token and
  re-auth via a flow that doesn't require the plaintext password. Blocked by LibreLinkUp's
  unofficial API not cleanly supporting this today.

**Definition of done:** production config uses a KMS whose master key is not resident on the
application VPS; a raw DB read shows only ciphertext; documented in the deploy runbook.

## 2. WebSocket token in query string (RESOLVED)

~~The interim glucose websocket auth uses `?token=`, which leaks into access/proxy logs.~~
`/ws/app/stream` and `/ws/device/stream` (architecture-v3.md §2.6) now authenticate via
`Sec-WebSocket-Protocol` (`app/services/realtime/ws_auth.py`), and the old `?token=`
`/ws/glucose` route is deleted (`app/api/websockets/glucose_stream.py`).

## 3. Pre-real-users security review (MEDIUM)

Before onboarding real users, a focused review of: credential handling end to end, device-token
lifecycle/revocation, rate-limit/abuse paths on pairing and Abbott polling, and PII in logs.

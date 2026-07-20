# AGENTS.md — flexisip-docker

## Project identity

Docker image build repository for two Belledonne Communications SIP components.
Not a source code repository. Delivers:

- **`ghcr.io/telecrypt-io/flexisip-proxy`** — SIP proxy (TLS port 5061)
- **`ghcr.io/telecrypt-io/flexisip-conference`** — Conference server (E2EE-capable)

Both images are built from upstream source and published to GHCR. Bonus `.deb`
packages are published to GitHub Releases (not consumed by Docker).

## ⚠️ Do NOT clone this repo onto a deployment server — COPY the files

**Rule: never `git clone` this repository onto a production host. Copy only
the files you need.**

**Why.** The deployment model has operators edit config files **in place** on
the server. In a clone, that working tree is attached to `.git` with a remote
pointing at this **public** repository. Real secrets — TURN credentials in
`.env`, HA1 password hashes in `config/users.conf` — then sit in a working
tree one `git commit -a && git push` from publication. On a live deployment
these were found **staged in the index**, which is one command from the same
outcome. An automated agent following a "commit your work" convention would
do exactly that, having no way to tell this repo from a private one.

`.env` and `config/users.conf` are now **untracked and gitignored** (they ship
as `.env.example` / `config/users.conf.example`), which removes the primary
hazard. **The copy-don't-clone rule still stands** as defence in depth: a
clone can still be pushed to, and `git add -f` or a future tracked file
re-opens the hole.

**What to copy** onto the server:

```
docker-compose.yml
versions.env
config/flexisip.conf
config/flexisip-conference.conf
config/domain-registrations.conf
.env.example              -> rename to .env,               then fill in + chmod 600
config/users.conf.example -> rename to config/users.conf,  then fill in + chmod 600
```

**Consequence — updates become manual.** Without a clone there is no
`git pull`; re-copy changed files deliberately and diff against your local
edits first. That is the intended trade-off: updates are rarer than
credential edits, and a deliberate diff is safer than a pull that could
revert a local security fix (see "Config drift" below).

**Middle path,** if you want easy updates: clone, then immediately
`git remote remove origin`. Updates become "add the remote, fetch, diff,
remove the remote again" — deliberate, with no standing push target.

**Never** commit real credentials to this repo. If it happens, treat the
credentials as compromised: rotate TURN credentials and every user password
(HA1 hashes are offline-crackable), then purge the history.

## Config drift — server-local edits are silently reverted by updates

Security and reliability fixes applied **only on a server** are lost the next
time the repo is updated. Observed on a live deployment: a fix binding SIP
UDP to loopback existed on the server for days but never upstream, so any
`git pull` would have silently re-exposed the unencrypted transport.

**Rule:** a change that is *security-relevant* or *generally correct* belongs
**upstream in this repo**, not in a local edit. Sanctioned local edits are
only: `<SIP_IP>` substitution, real credentials, and `.env` values. Anything
else is an upstream change. Before any update, diff the local config files
first.

## Findings from live-deployment review (2026-07)

Discovered while operating a real deployment. Recorded here so they are not
re-discovered the hard way. **Full detail in [`SECURITY.md`](SECURITY.md).**

- **Presence phones home to Belledonne.** Stock Linphone clients default to
  `sips:rls@sip.linphone.org` for presence, and an unrestricted
  `[module::Forward]` routes those subscriptions **out to the public
  Internet** — leaking account existence, online status, server IP and
  timing. Confirmed live via an established TLS connection to
  `sip11.linphone.org:5061`. **This contradicts the premise of a
  self-hosted deployment.** It is easy to dismiss as log noise. Detection
  commands and mitigations are in `SECURITY.md`; cutting it costs **zero**
  functionality because the subscriptions already fail with `404`.
- **E2EE does not cover metadata.** `log-level=message` retains
  who-called-whom records. Say "end-to-end encrypted media", not "we keep no
  records", unless you configured it that way.
- **`[module::DoSProtection]` disabled means fail2ban is REQUIRED**, not
  optional. Without it there is no rate limiting at any layer.
- **`[presence-server]` and `[module::Authorization]` blocks look like
  functional config but are warning suppressors.** Neither enables anything;
  deleting them removes no functionality and only restores log noise. Read
  the comment above a block before "cleaning it up."
- **`[module::MediaRelay]` does not weaken E2EE** — it forwards ZRTP
  ciphertext it cannot read. It is a CPU/bandwidth concern, not a
  confidentiality one.
- **Default datastore credentials ship weak on purpose** (MariaDB
  `flexisip`, Redis unauthenticated) and must be changed by an operator
  procedure — the no-runtime-substitution model means this repo cannot
  safely ship changed values. See `SECURITY.md`.
- **Beware `grep -c '503'` on proxy logs.** It massively overcounts —
  `503` appears inside connection IDs and dialled numbers. Grep
  `'503 Service Unavailable'`. On one deployment the naive count read 1533
  against 130 real occurrences.
- **`180 Ringing` → `408 Request Timeout` is ambiguous.** It is the
  signature of both an unanswered call and a push-notification failure. Logs
  cannot distinguish them; only a deliberate answered-call test can.

## Configuration model — configs are local and edited locally

`config/flexisip.conf`, `config/flexisip-conference.conf`, and `config/users.conf`
are **local files** mounted from the host. They are intended to be edited on the
deployment server — that is by design, not a workaround.

- The repo ships them **ready-to-use** with E2EE-capable defaults and a single
  `<SIP_IP>` placeholder; the deployer substitutes their public IP locally.
- **IP and domain management is deliberately local.** The entrypoints do **not**
  perform `<SIP_IP>` substitution at runtime (this was considered and rejected:
  configs are local files the operator owns). Do not "fix" this by adding in-container
  templating — it contradicts the supported deployment model.
- `.env` carries only environment-level values (`SIP_IP` for the ACME sidecar and
  containers, TURN credentials, `ENABLE_EKT_SERVER`). Everything else stays in the
  local config files.

## Workflow trigger rules

`.github/workflows/build.yml` only fires on changes to:

- `versions.env`
- `docker/**`
- `.github/workflows/build.yml`

**Config/docs changes (README, .env, docker-compose.yml, config/*.conf)
silently skip CI.** This is intentional — Dockerfiles are unchanged.

`.github/workflows/auto-bump.yml` runs nightly (03:00 UTC), detects new upstream
releases, and pushes `versions.env` updates to `main`.

## Version management

| File | Role |
|---|---|
| `versions.env` | Source of truth for which upstream version gets built |
| `state/built.json` | Source of truth for which versions have a published image |

Never edit `state/built.json` manually — it is updated by CI.

## Upstream source

GitLab (`gitlab.linphone.org`) is unreliable for submodule fetches. Both
Dockerfiles include retry+cleanup loops (nuking `.git/modules/*` between
retries). **If modifying Dockerfiles, preserve these loops.**

## Key commands

```bash
# Trigger a build (after changing versions.env)
gh workflow run build

# Check latest workflow runs
gh run list --limit 5

# Watch a running build
gh run watch <run-id>

# Pull images locally
docker pull ghcr.io/telecrypt-io/flexisip-proxy:latest
docker pull ghcr.io/telecrypt-io/flexisip-conference:latest
```

## No PRs

Push directly to `main`. No branch protection or PR gates configured.

## Permissions

The `build-debs` job needs `permissions: contents: write` override (top-level
permissions are `contents: read`). Do not remove this.

## ACME / TLS automation

- ACME sidecar (`goacme/lego:v5.2.2`) fetches Let's Encrypt IP certificates
  via HTTP-01 challenge.
- **Port 80/tcp must be reachable** from the Internet on `SIP_IP`.
- Let's Encrypt IP certs are short-lived (~6 days), renewed automatically.
- No DNS required — IP-address certificates only.
- No email required — Let's Encrypt account is created without email.
- Certificate + key are written to shared `flexisip_certs` Docker volume.
- Proxy auto-reloads certs every 60 seconds.

## Config placeholders

All config files use `<SIP_IP>` as a placeholder. Never hardcode IPs in
committed files. The user replaces `<SIP_IP>` with their server's public IP
during setup.

DB passwords are hardcoded to `flexisip` (internal only — MariaDB is not
exposed to the Internet). TURN credentials must be changed from defaults
(exposed to Internet on ports 3478/5349).

**TURN credential generation:** When helping a deployer fill in `TURN_USER`
and `TURN_PASSWORD`, always generate them via shell commands (e.g.
`openssl rand -hex 12`) rather than outputting strings directly. LLMs
mis-handle credential strings — output may contain invisible characters,
formatting artifacts, or be difficult to copy correctly. Shell commands
produce verified, copy-paste-safe values.

## E2EE

- **Enabled by default** in `config/flexisip-conference.conf` (`[conference-server]`
  `audio-engine-mode=sfu`, `video-engine-mode=sfu`, `encryption=zrtp`). No runtime
  rewriting — the config ships ready.
- `ENABLE_EKT_SERVER=true` in `.env` is retained only as an **intent signal**; it no
  longer triggers any entrypoint config change.
- EKT plugin is always installed but only active in SFU mode.
- **Verify:** conference log line
  `EKT server plugin for core sip:conference-focus@… has been succesfully loaded`
  and `E2EE mode ACTIVE`.
- **To disable E2EE:** comment out the three `audio-engine-mode`/`video-engine-mode`/
  `encryption` lines in `config/flexisip-conference.conf`. (Media then unencrypted;
  flexisip raises no error.)
- **EKT module license:** Provided by Belledonne Communications. For proprietary
  license holders, a separate license may be required. For AGPLv3 self-hosting
  (this project's purpose), it is freely usable. See `NOTICE`.
- **No liability:** Author(s) bear no responsibility for misuse. See `NOTICE`.

## Configuring E2EE — in a flash (for LLMs and operators)
E2EE group conferences work out of the box. Nothing is rewritten at runtime.
1. `config/flexisip-conference.conf` already contains, under `[conference-server]`:
     audio-engine-mode=sfu
     video-engine-mode=sfu
     encryption=zrtp
   Leave them as-is (uncomment only if ever absent).
2. `.env` keeps `ENABLE_EKT_SERVER=true` as an intent signal (no rewriting).
3. Deploy: `docker compose up -d`.
4. Verify: `docker logs flexisip-conference 2>&1 | grep -E "EKT server plugin|E2EE mode ACTIVE"`
   Expect both lines. If missing, E2EE is NOT active (media unencrypted).
To DISABLE E2EE: comment the three lines in step 1.

## Key files

| File | Purpose |
|---|---|
| `docker-compose.yml` | Deployment layout (proxy, conference, acme, mariadb, redis, coturn) |
| `config/flexisip.conf` | Proxy config template |
| `config/flexisip-conference.conf` | Conference config template |
| `.env` | Environment variables template |
| `docker/proxy/Dockerfile` | Proxy image build |
| `docker/conference/Dockerfile` | Conference image build |
| `docker/proxy/entrypoint.sh` | Proxy entrypoint (EKT_SERVER toggle) |
| `.github/workflows/build.yml` | CI build pipeline |
| `.github/workflows/auto-bump.yml` | Nightly upstream version detection |
| `versions.env` | Pinned upstream versions |
| `state/built.json` | Published image versions (CI-managed) |
| `SECURITY.md` | E2EE verification and threat model |
| `NOTICE` | Attribution and license details |

## Testing

Smoke test (`build.yml` job 4) checks:
- OCI labels present on both images
- `entrypoint.sh` exists in both images
- `*ektserver*.so` exists in conference image at
  `/opt/belledonne-communications/flexisip-conference/lib/liblinphone/plugins/`

No unit tests. Verification is manual against a running deployment.

## Known issues

- **auth-domains-mode=legacy warning:** Previously emitted by both proxy and
  conference at startup (from upstream Flexisip v2.6 defaults). Now suppressed
  in both config/flexisip.conf and config/flexisip-conference.conf via a
  [module::Authorization] section with auth-domains-mode=static.

- **users.conf has NO comments:** Flexisip's authdb parser rejects # comments
  anywhere in the file. config/users.conf contains only version:1 + credential
  lines. The format is documented in README.md (Quick start) instead.

- **`tcp:` transport prefix crashes the proxy:** flexisip 2.6 only accepts
  `sip:` (UDP) and `sips:` (TLS) in `transports`. A `tcp:` prefix →
  "could not enable transport … Invalid argument" crash-loop. The proxy uses
  both `sip:` (5060, the proxy→conference UDP hop) and `sips:` (5061, client TLS).

- **Conference server runs on host networking** (`network_mode: host`): it binds
  127.0.0.1:6064 and the proxy reaches it via loopback. Because Docker service
  names don't resolve under host networking, the conference config points
  MariaDB/Redis at 127.0.0.1 (published on loopback in docker-compose.yml).

- **MediaRelay enabled (`enabled=true`):** engages automatically on NAT legs.
  flexisip 2.6 does NOT accept `force-relay` / `relay-ips` in that section.

- **Conference routing is automatic:** no `conference-factory-uri` proxy directive
  (invalid in v2.6) — the conference server registers its factory URI with the
  proxy's registrar.

- **Reference client is Linphone** (baresip can't do group E2EE / LIME+EKT).
  Multi-client testing on one host collides on RTP port 7078 — isolate clients
  in separate network namespaces. Headless testing needs a pulseaudio null sink.
  mbedTLS Linphone clients may reject the 2025 Let's Encrypt chain; never ship
  `verify_server_certs=0` in production.

- **E2EE is on by default** — `config/flexisip-conference.conf` ships
  `audio-engine-mode=sfu` + `video-engine-mode=sfu` + `encryption=zrtp`;
  `ENABLE_EKT_SERVER=true` in `.env` is an intent signal only. With E2EE off
  (the three lines commented), conferences still work but media is NOT
  ZRTP-encrypted and flexisip raises no error (silently absent E2EE). Verify via
  the conference log line
  `EKT server plugin for core sip:conference-focus@… has been succesfully loaded`.

- **`482 Loop Detected` on client REGISTER — root cause `reg-on-response`:**
  `config/flexisip.conf` sets `reg-on-response=false` (this proxy is the terminal
  registrar). With `true`, the Registrar forwards each REGISTER to the domain's
  next hop; in a single-proxy deployment that next hop is the proxy itself →
  self-forward → `482 Loop Detected` on every client REGISTER. The conference
  server registers over `127.0.0.1` and slipped past the loop check, masking the
  bug. **Keep `reg-on-response=false` unless a proxy is chained in front.**
- **`482 Loop Detected` on INVITE / forward-loop (upstream #187):** an INVITE from
  a NATed client whose visible source IP equals the proxy's own public IP can be
  misclassified as a routing loop. Mitigate with client STUN/TURN (coturn,
  included) so clients advertise a public/relay Contact, and keep
  `aliases=<SIP_IP>` in `[global]`. Test with genuinely remote clients — same-host
  netns masquerade presenting the server's own IP is a false-positive.

- **Re-register after proxy restart:** Redis-persisted bindings go stale on
  `docker restart flexisip-proxy` → `404`/`482` until clients re-register.
  Restart clients or shorten `default-expires` during rollout.

- **Healthchecks added (Issue 7):** compose now health-checks mariadb, redis,
  coturn (UDP 3478), proxy (TCP 5061), conference (UDP 6064). Monitor proxy
  `503`s, cert expiry, conference failures, RTP-relay.

- **DoSProtection disabled:** The `[module::DoSProtection]` section in
  `config/flexisip.conf` sets `enabled=false` because the module
  requires iptables, which is not available (or desirable) inside Docker
  containers. For production DoS protection, use external mechanisms (cloud
  firewalls, fail2ban, etc.).

## Handover docs

`handover/` directory contains additional context:
- `QUICK-HANDOVER.md` — project overview and critical runtime config
- `SESSION-NOTES.md` — session context
- `SOURCE-EXCERPTS.md` — upstream source excerpts
- `meta-repo-template/` — template for meta-repository structure

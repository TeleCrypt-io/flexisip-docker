# AGENTS.md — flexisip-docker

## Project identity

Docker image build repository for two Belledonne Communications SIP components.
Not a source code repository. Delivers:

- **`ghcr.io/telecrypt-io/flexisip-proxy`** — SIP proxy (TLS port 5061)
- **`ghcr.io/telecrypt-io/flexisip-conference`** — Conference server (E2EE-capable)

Both images are built from upstream source and published to GHCR. Bonus `.deb`
packages are published to GitHub Releases (not consumed by Docker).

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

- Opt-in via `ENABLE_EKT_SERVER=true` on the conference container.
- Requires SFU mode (`audio-engine-mode=sfu`, `video-engine-mode=sfu`, `encryption=zrtp`).
- EKT plugin is always installed but only active in SFU mode.
- **EKT module license:** Provided by Belledonne Communications. For proprietary
  license holders, a separate license may be required. For AGPLv3 self-hosting
  (this project's purpose), it is freely usable. See `NOTICE`.
- **No liability:** Author(s) bear no responsibility for misuse. See `NOTICE`.

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

- **E2EE is on by default** (`ENABLE_EKT_SERVER=true` in `.env`). With it off,
  conferences still work but media is NOT ZRTP-encrypted and flexisip raises no
  error (silently absent E2EE). Verify via the conference log line
  `EKT server plugin for core sip:conference-focus@… has been succesfully loaded`.

- **`482 Loop Detected` on NATed REGISTER (upstream issue #187):** a REGISTER
  whose visible source IP equals the proxy's own public IP is rejected as a loop.
  Mitigate with client STUN/TURN (coturn, included) so clients advertise a
  public/relay Contact, and keep `aliases=<SIP_IP>` in `[global]`. Test with
  genuinely remote clients — same-host netns masquerade presenting the server's
  own IP is a false-positive and not representative.

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

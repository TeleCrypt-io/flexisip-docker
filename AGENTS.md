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

**Config/docs changes (README, .env.example, docker-compose.yml, config/*.conf.example)
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

- ACME sidecar (`goacme/lego:v4.31.0`) fetches Let's Encrypt IP certificates
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
| `config/flexisip.conf.example` | Proxy config template |
| `config/flexisip-conference.conf.example` | Conference config template |
| `.env.example` | Environment variables template |
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

## Handover docs

`handover/` directory contains additional context:
- `QUICK-HANDOVER.md` — project overview and critical runtime config
- `SESSION-NOTES.md` — session context
- `SOURCE-EXCERPTS.md` — upstream source excerpts
- `meta-repo-template/` — template for meta-repository structure

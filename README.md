# TeleCrypt-io flexisip-docker

**Unofficial community build** of the Belledonne Flexisip SIP proxy and the
`flexisip-conference` server, packaged as Docker images on GitHub Container
Registry.

This repository does **not** contain the upstream source. It builds and publishes
two Docker images whose tags track upstream version numbers. The two
upstream components are versioned independently; each component has its own
image and its own version stream.

This is **not** an official Belledonne Communications image. It is a community
build for self-hosting.

## Contract: upstream version = Docker image tag

For every stable release of `flexisip` and `flexisip-conference`, this
repository automatically builds a Docker image whose tag equals the upstream
version, and pushes it to GHCR. A nightly workflow (`.github/workflows/auto-bump.yml`)
monitors both upstream repositories and triggers the build on new releases.

| Upstream | Image | Tag examples |
|---|---|---|
| `flexisip` | `ghcr.io/telecrypt-io/flexisip-proxy` | `2.6.0`, `latest` |
| `flexisip-conference` | `ghcr.io/telecrypt-io/flexisip-conference` | `1.0.0`, `latest` |

The versioned tag is the primary deliverable. `:latest` is a convenience alias
that always points to the most recently published version.

## What's in the box

Two Docker images:

- **`flexisip-proxy`** — SIP proxy. Owns the TLS port (5061). Manages user
  registration and SIP routing.
- **`flexisip-conference`** — Conference server. Handles group chat and
  audio/video conferences. Includes the EKT plugin (`linphone_ektserver.so`)
  so that conferences can be end-to-end encrypted when configured.

Both images are based on `ubuntu:24.04` and install the Belledonne `.deb`
packages built from upstream source by this repository's CI.

## Automatic TLS via Let's Encrypt IP certificates

The deployment includes an **ACME sidecar** (`goacme/lego`) that automatically
fetches and renews a Let's Encrypt **IP-address TLS certificate** using the
HTTP-01 challenge.

**How it works:**

1. The `acme` container starts and requests a certificate for your public IP
   from Let's Encrypt via HTTP-01 (port 80).
2. The certificate (`cert.pem`) and private key (`privkey.pem`) are written
   into a shared Docker volume (`flexisip_certs`).
3. The `proxy` container mounts this volume at `/etc/flexisip/tls/` (read-only)
   and auto-reloads the certificates every 60 seconds.
4. The ACME container runs a renewal loop every 12 hours, checking if renewal
   is needed (certs are renewed when <3 days remain).

**Requirements:**

- **Port 80/tcp** must be reachable from the Internet on your `SIP_IP`
  (HTTP-01 challenge validation).
- Let's Encrypt issues IP certs as **short-lived certificates** (~6 days).
  Renewal is fully automatic — no manual intervention needed.

**No DNS required.** This solution uses IP-address certificates, so you don't
need a domain name or DNS API access.

## End-to-end encryption (opt-in)

E2EE conferences are **not** the default. The conference server's default
audio mode is `mixer`, which decodes/mixes/re-encodes media and is
**incompatible** with true E2EE.

To enable E2EE, set `ENABLE_EKT_SERVER=true` on the conference container.
The entrypoint script then appends the E2EE configuration to
`flexisip-conference.conf`:

```ini
[conference-server]
audio-engine-mode=sfu
video-engine-mode=sfu
encryption=zrtp
```

These three lines switch the conference to **SFU mode** (server only forwards
RTP packets and rewrites headers, no decode/encode), which is what makes E2EE
possible. The EKT plugin (always installed) distributes encryption keys.

**EKT plugin license:** The EKT server plugin is provided by **Belledonne
Communications** under the terms described in the upstream
`ENABLE_EKT_SERVER` CMake option. For customers under a proprietary license,
this functionality requires a specific license from Belledonne Communications.
For AGPLv3 self-hosting (which this repository is built for), the plugin is
freely usable. See `NOTICE` for the full attribution and `SECURITY.md` for
verification steps.

## Quick start

```bash
# 1. Clone this repo
git clone https://github.com/TeleCrypt-io/flexisip-docker.git
cd flexisip-docker

# 2. Edit the config files (already in the repo)
# Replace <SIP_IP> with your server's public IP in:
#   config/flexisip.conf
#   config/flexisip-conference.conf
#   config/users.conf   (also set real SIP credentials — format below)
# NOTE: config/domain-registrations.conf is already provided (empty) — leave it.
#
# users.conf format (NO comments allowed — Flexisip rejects # anywhere):
#   version:1
#   <user>@<domain> <algo>:<password> ;
# Supported algorithms: clrtxt, md5, sha256. The " ;" terminator is mandatory.
# Example:  version:1\n  test@203.0.113.10 clrtxt:test1234 ;

# 3. Edit .env (already in the repo)
# Set SIP_IP, TURN credentials

# 4. Pull and start (port 80 must be reachable for ACME challenge)
docker compose pull
docker compose up -d
docker compose logs -f acme proxy conference
```

The ACME sidecar will automatically obtain a TLS certificate on first start.
The proxy will begin serving SIP over TLS once the certificate is available
(usually within 30-60 seconds).

For E2EE:

```bash
# In .env:
ENABLE_EKT_SERVER=true

# Then:
docker compose up -d
```

## Important configuration notes

- **Transports:** flexisip 2.6 accepts only `sip:` (UDP) and `sips:` (TLS)
  prefixes in `transports`. A `tcp:` prefix crashes the proxy. The proxy is
  configured with both `sips:0.0.0.0:5061` (client TLS) and
  `sip:0.0.0.0:5060` (internal hop to the conference server's UDP contact).
- **Conference server is on host networking** (`network_mode: host`). It binds
  `127.0.0.1:6064` and the host-networked proxy reaches it via loopback. Under
  host networking Docker service names don't resolve, so its MariaDB/Redis point
  at `127.0.0.1` (both published on loopback in `docker-compose.yml`) — MariaDB
  is **not** exposed to the Internet.
- **MediaRelay** is enabled (`[module::MediaRelay] enabled=true`). flexisip 2.6
  does not accept `force-relay` / `relay-ips` in that section; the module engages
  automatically on NAT-detected legs.
- **Conference routing is automatic** — the conference server registers its
  factory URI with the proxy's registrar; no proxy route directive is needed
  (an old `conference-factory-uri` key is invalid in v2.6).

## Production considerations

- **E2EE is on by default** (`ENABLE_EKT_SERVER=true` in `.env`). If you set it
  to `false`, conferences still work but media is **not** ZRTP-encrypted — and
  flexisip raises **no error**, so E2EE is silently absent. Verify it is active
  by grepping the conference log for:
  `EKT server plugin for core sip:conference-focus@… has been succesfully loaded`.

- **Behind-NAT clients / `482 Loop Detected` (upstream issue
  [#187](https://github.com/BelledonneCommunications/flexisip/issues/187)):**
  a `REGISTER` from a client behind NAT whose visible source IP equals the
  proxy's own public IP is rejected with `482 Loop Detected` (the proxy thinks
  the request looped back to itself). Reliable mitigations:
  1. Configure clients with **STUN/TURN** (coturn is included — point the client
     at `stun:<SIP_IP>:3478` / `turn:<SIP_IP>:3478?transport=udp` using the
     `TURN_USER`/`TURN_PASSWORD` from `.env`) so they advertise a
     public/relay Contact.
  2. Keep `aliases=<SIP_IP>` in `[global]` (already set) so the proxy's
     self-identity is unambiguous.
  Test with genuinely remote clients — a same-host netns masquerade that presents
  the server's own IP triggers the false loop and is not representative.

- **Re-register after a proxy restart:** registrar bindings persist in Redis, so
  after `docker restart flexisip-proxy` clients with now-stale bindings may get
  `404`/`482` until they re-register. Restart clients, or use a shorter
  `default-expires` in `[module::Registrar]` during rollout.

- **Conference lifecycle:** finished-conference state is pruned automatically in
  MariaDB. Participant limits are governed by `max-contacts-per-registration`
  (proxy) and the conference server's internal limits — tune for your scale.

- **Monitoring / healthchecks:** compose ships healthchecks for `mariadb`,
  `redis`, `coturn`, `proxy`, and `conference`. Alert on proxy `503`s, TLS cert
  expiry (renewed automatically ~every 6 days by lego), conference-server
  failures, and RTP-relay health.

- **TURN/ICE client example (Linphone):** set the STUN server to
  `stun:<SIP_IP>:3478` and the TURN server to
  `turn:<SIP_IP>:3478?transport=udp` with the credentials from `.env`. This is
  required for clients behind symmetric NAT to establish media.

## Testing notes

- **Use Linphone as the reference client.** `baresip` cannot do group E2EE
  (no LIME/EKT). `linphone-cli` ≥ 5.2 works (native on Ubuntu 24.04).
- **Two clients on one host collide on RTP port 7078** (SO_REUSEPORT). For
  multi-client testing on a single machine, isolate each client in its own
  network namespace, or use separate hosts.
- **Headless servers need an audio source** or RTP/ZRTP never flows. Use a
  pulseaudio null sink (`module-null-sink`) and point clients at it.
- **Let's Encrypt / mbedTLS CA caveat:** mbedTLS-based Linphone clients may
  reject the 2025 Let's Encrypt chain even when `openssl s_client` validates it.
  Do **not** ship `verify_server_certs=0` in production — ensure the client CA
  bundle is current and document the caveat instead.

## How the build works

`.github/workflows/build.yml` runs on push to `main` and on manual trigger.
It has five jobs:

1. **`build-debs`** (bonus) — clones both `flexisip` and `flexisip-conference` at
   the tags in `versions.env`, builds `.deb` packages with `CPACK_GENERATOR=DEB`,
   and publishes them to a GitHub Release.  Runs only when `versions.env` has
   been modified.
2. **`build-proxy-image`** — multi-stage Docker build (`docker/proxy/Dockerfile`).
   Clones the `flexisip` repo and its submodules from upstream source, builds
   the proxy and its dependencies (linphone-sdk, mbedtls, soci, etc.), then
   produces a minimal runtime image pushed to GHCR with both `:<version>` and
   `:latest` tags.
3. **`build-conference-image`** — same for `flexisip-conference`, with
   `-DENABLE_EKT_SERVER=ON` so the EKT plugin is included in the image.
4. **`smoke-test`** — pulls both freshly-built images, inspects their OCI
   labels and entrypoints, and verifies the EKT plugin is present in the
   conference image.
5. **`publish-state`** — on full success, records the built versions in
   `state/built.json`.

`.github/workflows/auto-bump.yml` runs nightly. It queries the GitLab API
for the latest stable tag of each upstream. If a newer version exists that
isn't already in `state/built.json`, it updates `versions.env` and pushes
to `main`, which triggers the build.

`versions.env` is the source of truth for which upstream version is built.
`state/built.json` is the source of truth for which versions have produced
a published image.

## Source

Upstream projects (Belledonne Communications, dual-licensed AGPLv3 / proprietary):

- Flexisip: <https://gitlab.linphone.org/BC/public/flexisip>
- flexisip-conference: <https://gitlab.linphone.org/BC/public/flexisip-conference>
- Linphone SDK (transitive): <https://gitlab.linphone.org/BC/public/linphone-sdk>

## License

This repository's build scripts and Dockerfiles are licensed under AGPL-3.0
(see `LICENSE`). The upstream projects remain under their original dual
license. By using the published images, you accept the AGPLv3 terms.

The EKT plugin's upstream CMake option notes that "for customers under a
proprietary license, this functionality is under a specific license." The
plugin's own README declares GNU AGPLv3. This build treats the plugin as
AGPL-compatible and includes it in the conference image. See `NOTICE` for
the full attribution.

## Disclaimer

This is an **unofficial community build**. It is not endorsed by, affiliated
with, or supported by Belledonne Communications.

This repository is a build wrapper for freely available open-source software
(AGPLv3-licensed Flexisip and flexisip-conference by Belledonne Communications).
It does not contain original proprietary code. The EKT server plugin is provided
as part of the upstream open-source project under the conditions described in
`NOTICE`.

**No responsibility for misuse.** The author(s) of this repository bear no
responsibility or liability for any misuse, damage, or legal consequences
arising from the use of the software, images, or configurations provided
herein. Use at your own risk. Consult a qualified lawyer for legal advice
regarding AGPL compliance, EKT licensing, or deployment in your jurisdiction.

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

See `SECURITY.md` for the E2EE verification checklist and the client-side
indicators.

## Quick start

```bash
# 1. Clone this repo
git clone https://github.com/TeleCrypt-io/flexisip-docker.git
cd flexisip-docker

# 2. Create your config from the examples
mkdir -p config certs
cp config/flexisip.conf.example config/flexisip.conf
cp config/flexisip-conference.conf.example config/flexisip-conference.conf
# Edit both files: set SIP_DOMAIN, change DB password, point TLS certs to ./certs

# 3. Place your TLS cert and key in ./certs/agent.pem and ./certs/agent.key

# 4. Create your .env from the example
cp .env.example .env
# Edit .env: set SIP_DOMAIN, TURN_PUBLIC_IP, rotate passwords

# 5. Pull and start
docker compose pull
docker compose up -d
docker compose logs -f proxy conference
```

For E2EE:

```bash
# In .env:
ENABLE_EKT_SERVER=true

# Then:
docker compose up -d
```

## How the build works

`.github/workflows/build.yml` runs on push to `main` and on manual trigger.
It has four jobs:

1. **`build-proxy-deb`** — clones `flexisip` at the tag in `versions.env`,
   configures with `CPACK_GENERATOR=DEB`, builds, uploads the `.deb`.
2. **`build-conference-deb`** — same for `flexisip-conference`, with
   `-DENABLE_EKT_SERVER=ON` so the EKT plugin subpackage is produced.
3. **`build-proxy-image`** — installs the proxy `.deb` in the proxy image
   and pushes it to GHCR with both `:<version>` and `:latest` tags.
4. **`build-conference-image`** — same for the conference image.
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
with, or supported by Belledonne Communications. Use at your own risk; consult
a lawyer if you have any concerns about the AGPL terms in your jurisdiction.

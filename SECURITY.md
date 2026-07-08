# Security and E2EE

This document explains what end-to-end encryption (E2EE) means in a Flexisip
deployment, how the EKT plugin provides it, and how to verify the deployment
is actually using it.

## What is and isn't E2EE

A conference is **end-to-end encrypted** when the audio/video media streams
are encrypted by the sender client and decrypted only by the recipient
clients. The conference server must be able to forward the encrypted packets
without being able to decrypt them.

This is **not** the same as TLS or SRTP. Those protect media between the
client and the server, but the server decrypts and re-encrypts on the other
side. With E2EE, the server has no way to read the media.

| State | Server can read media? | Encryption hops |
|---|---|---|
| **Unencrypted** (no SRTP) | Yes | None |
| **SRTP to server** (default Flexisip `mixer` mode) | Yes | Client → Server |
| **ZRTP / SRTP-DTLS to server** | Yes (in mixer mode) | Client → Server |
| **E2EE conference (SFU + EKT)** | **No** | Client → Client |

In Flexisip's default audio mode (`mixer`), the server decodes every stream,
mixes them, and re-encodes the mixed result. The server necessarily sees the
raw media, so the conference cannot be end-to-end encrypted regardless of
any transport encryption.

To get true E2EE, the conference must run in **SFU mode**: the server only
forwards RTP packets and rewrites a few RTP header fields, never decoding
or re-encoding. SFU mode is configured by:

```ini
[conference-server]
audio-engine-mode=sfu
video-engine-mode=sfu
encryption=zrtp
```

The `flexisip-conference` image's entrypoint appends this block automatically
when the container is started with `ENABLE_EKT_SERVER=true`.

## The EKT plugin

The EKT plugin (`linphone_ektserver.so`, included in the conference image)
implements **RFC 8870 Encrypted Key Transport** combined with **RFC 8723
double-SRTP**. It runs inside the conference server and dispatches the
per-conference encryption key to all participants via SIP
PUBLISH / SUBSCRIBE / NOTIFY. Each client then uses the EKT key to derive
the inner SRTP key that protects media between clients.

Without the EKT plugin, `flexisip-conference` cannot establish E2EE
conferences. The plugin is always installed in the conference image but only
takes effect when SFU mode is configured.

## Verifying E2EE in a running deployment

1. **Plugin present:**
   ```bash
   docker exec flexisip-conference ls -l \
     /opt/belledonne-communications/flexisip-conference/lib/liblinphone/plugins/linphone_ektserver.so
   ```

2. **Plugin loaded at startup:**
   ```bash
   docker logs flexisip-conference 2>&1 | grep -i "EKT server plugin"
   ```
   Expected: `EKT server plugin for core ... has been successfully loaded`

3. **Conference in SFU mode:**
   ```bash
   docker exec flexisip-conference \
     grep -E "audio-engine-mode|video-engine-mode|encryption" \
     /etc/opt/belledonne-communications/flexisip-conference/flexisip-conference.conf
   ```
   Expected: `audio-engine-mode=sfu`, `video-engine-mode=sfu`, `encryption=zrtp`

4. **Client-side indicator:** A Linphone client in an E2EE conference shows
   a padlock with the label "End-to-end encrypted" (or similar, depending on
   client version and platform). See the table below.

5. **Programmatic check:** `liblinphone` exposes
   `linphone_conference_get_security_level()`. A correct E2EE conference
   returns `LinphoneConferenceSecurityLevelEndToEnd`. The other values are
   `None` (unencrypted) and `PointToPoint` (only encrypted to the server).

   A test program can be built against `liblinphone` headers and run
   against the live conference to confirm this.

## Client UI indicators (verified from upstream wiki and changelogs)

| State | Linphone indicator (desktop & mobile) |
|---|---|
| Unencrypted | Red padlock with slash |
| SRTP (transport only, server terminates media) | Green padlock |
| **E2EE conference (LIME + EKT active)** | **Padlock + "End-to-end encrypted" label** |
| Misleading legacy label (pre-6.1.1) | "End-to-end encrypted call" may appear when only the leg to the server is E2EE; fixed in linphone-desktop 6.1.1+ |

The desktop changelog (6.1.1) explicitly notes the fix:

> Fixed "End-to-end encrypted call" label while in conference, the call may
> be end-to-end encrypted but only to the conference server, not to all
> participants.

When verifying, ensure all clients joining the conference show the
"End-to-end encrypted" indicator. If only some clients do, the E2EE
negotiation has not completed for all participants.

## Threat model notes

- The conference server **authenticates participants** but does not need
  to know the EKT key. The key is distributed over SIP signaling, but the
  SIP signaling itself is end-to-end authenticated via the EKT key exchange.
- **Active MITM:** prevented by the EKT key agreement (RFC 8870 § 5.2).
  An attacker who can rewrite SIP signaling cannot derive the EKT key.
- **Compromised server:** cannot read media. The EKT key is per-conference
  and is only revealed to the participants, not the server.
- **Compromised client:** can read its own media and impersonate that
  client, but cannot decrypt other participants' media.
- **Replay / reordering:** handled by SRTP sequence numbers inside the
  EKT-protected inner SRTP.

## Trusting the EKT license

Upstream code declares the EKT plugin under GNU AGPLv3. The upstream
CMake option for EKT (`ENABLE_EKT_SERVER`) carries this note:

> For customers under a proprietary license, this functionality is under
> a specific license.

This means Belledonne may require a commercial license for some deployment
scenarios (e.g. proprietary redistribution of binaries or hosted service
without source disclosure). For AGPL-3.0 self-hosting — which is what this
repository is built for — the plugin is freely usable. **This is not legal
advice**; consult a lawyer if in doubt.

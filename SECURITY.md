# Security

Side Feather is a native plug-in loaded into Adobe Premiere Pro. Download reviewed builds from this repository's Releases page or the linked Harwich Dev listing. The release includes SHA-256 checksums.

The plug-in has no network listener, account, telemetry or remote-command interface. It processes Premiere-supplied image buffers in the host process. Native plug-ins share the host's process privileges; this is not an application sandbox.

The installer writes only the per-user Adobe MediaCore plug-in location and Side Feather's local plug-in backup location. It does not require an administrator password, alter Gatekeeper, enable developer mode or change system security settings.

## Report a vulnerability

Use [GitHub private vulnerability reporting](https://github.com/mathewharwich/side-feather/security/advisories/new) when available, or email [support@dev.mathewharwich.com](mailto:support@dev.mathewharwich.com). Avoid publishing exploit details or private media in a public issue.

This is an initial public beta. Security fixes will be considered for the latest published release; there is no guaranteed response time or long-term support commitment.

# Public release packaging

The public artifact is built separately from the original host-tested local
bundle. No source-function changes are made for public distribution.

1. `bash scripts/build-public.sh` rebuilds both architectures with source-path
   remapping, removes debug information, checks for private paths, and signs the
   staged plug-in using an existing Developer ID Application identity.
2. The installer is built from `release/installer/` with the staged plug-in in
   its Resources. The packager signs the nested plug-in before the installer.
3. `scripts/package-public.py` assembles only an explicit allowlist of release
   documents, the signed installer and plug-in. It builds a read-only compressed
   disk image and a manual-install ZIP, and writes SHA-256 checksums.
4. With an existing notarytool Keychain profile, submit the disk image to Apple,
   wait for acceptance, staple the ticket and validate Gatekeeper. Do not publish
   a package labelled notarized until those operations have passed.

The public source/release version is `v0.1.0-beta.1`. The plug-in's saved-effect
identifier and internal 0.1.0 build 3 metadata remain stable so existing Premiere
projects keep their effect identity.

No credentials, private release logs, internal tool receipts, actual user media,
QA exports, compiler intermediates, or previous plug-in builds belong in a
download. Use the packager's allowlist and audit rather than archiving a working
directory. Source archives should come from the separate public Git repository.

The installed plug-in uses the per-user MediaCore folder. Removal moves the
identified plug-in to a dated backup; it does not delete projects or media.

Apple's distribution instructions:
https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution

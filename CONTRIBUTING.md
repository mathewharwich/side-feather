# Contributing

Bug reports, small fixes and focused improvements are welcome. Please open an issue before starting a large change so the intended behavior is clear.

## Build and test

See the [README](README.md) for the macOS build requirements. Run `bash scripts/check.sh` for the host-independent C++ checks. CI runs those checks on Linux and macOS and builds the native effect on macOS. Signing and notarization require the release maintainer's own Apple credentials and are not part of ordinary contributor builds.

Preserve existing project compatibility: parameter IDs, control order and the native effect match name must not change casually. Changes to frame geometry, alpha, pixel formats, row strides or render flags need meaningful tests and live Premiere checks. Generated native-host QA fixtures are available through `tests/create_qa_assets.py`.

Contributions are provided under the repository's MIT license. Do not submit private projects, personal media, credentials, Adobe SDK archives or third-party assets without permission.

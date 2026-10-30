# Third-party components

This project builds against the published `after-effects` Rust bindings, using
their included generated API declarations. No downloaded Adobe SDK archive or
Adobe executable is bundled. Adobe Premiere Pro and After Effects are trademarks
of Adobe Inc.; this effect is independent of Adobe.

- `after-effects` 0.4.0 and `after-effects-sys` 0.4.0, Adrian Eddy and Moritz Moeller.
  Registry license: Apache-2.0 OR BSD-3-Clause OR MIT OR Zlib.
  Source: https://github.com/virtualritz/after-effects/
- `pipl` 0.1.1 (build time), same source. License: MIT OR Apache-2.0.
- `cc` 1.2.65 (build time), Alex Crichton and contributors. License: MIT OR Apache-2.0.
  Source: https://github.com/rust-lang/cc-rs

`Cargo.lock` pins all transitive package versions and registry checksums. Cargo
retrieves source packages and their author-provided notices from crates.io.
For the complete resolved license and source inventory, run:

```sh
cargo metadata --format-version 1 --locked > dependency-inventory.json
```

Full reproduced notices are in [licenses/THIRD_PARTY_LICENSES.txt](licenses/THIRD_PARTY_LICENSES.txt), with the resolved dependency inventory and Rust standard-library copyright files alongside it. The distributed plug-in also retains these notices in its Resources/Legal folder.

Contributor builds use ad-hoc signatures. The public beta is signed with Developer ID and is not notarized by Apple; see the installation section of the README.

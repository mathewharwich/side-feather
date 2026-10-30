#!/usr/bin/env python3
"""Build allowlisted public downloads; never archive a working directory wholesale."""
from __future__ import annotations

import argparse
import hashlib
import html.parser
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import urllib.request

REPOSITORY = "https://github.com/mathewharwich/side-feather"
DOCS = ["README.md", "PRIVACY.md", "SUPPORT.md", "SECURITY.md", "CHANGELOG.md", "CONTRIBUTING.md", "LICENSE", "docs/VERIFICATION.md", "docs/images/side-feather-demo.png"]
PRIVATE_MARKERS = [b"/Users/", b"/home/", b"/private/var/", b"/private/tmp/", b"/tmp/"]
MIT_TERMS = """Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
of the Software, and to permit persons to whom the Software is furnished to do
so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
"""


def run(*args: str, **kwargs):
    return subprocess.run(args, check=True, **kwargs)


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def audit(root: Path) -> int:
    count = 0
    for path in root.rglob("*"):
        if path.is_symlink():
            raise SystemExit(f"Release contains a symlink: {path.relative_to(root)}")
        if not path.is_file():
            continue
        data = path.read_bytes()
        for marker in PRIVATE_MARKERS:
            if marker in data:
                raise SystemExit(f"Private path marker {marker!r} in {path.relative_to(root)}")
        if path.name in {".DS_Store", ".env"} or path.suffix.lower() in {".mov", ".mp4", ".prproj", ".log", ".p8", ".p12"}:
            raise SystemExit(f"Unexpected private/build artifact: {path.relative_to(root)}")
        count += 1
    return count


class PlainText(html.parser.HTMLParser):
    def __init__(self):
        super().__init__()
        self.parts: list[str] = []

    def handle_data(self, data):
        self.parts.append(data)

    def handle_starttag(self, tag, attrs):
        if tag in {"p", "div", "h1", "h2", "h3", "li", "pre", "br"}:
            self.parts.append("\n")


def generate_licenses(source: Path, output: Path):
    metadata = json.loads(subprocess.check_output([
        "cargo", "metadata", "--manifest-path", str(source / "Cargo.toml"),
        "--locked", "--format-version", "1", "--filter-platform", "x86_64-apple-darwin",
    ], text=True))
    packages = {p["id"]: p for p in metadata["packages"]}
    nodes = {n["id"]: n for n in metadata["resolve"]["nodes"]}
    selected: set[str] = set()

    def visit(package_id):
        if package_id in selected:
            return
        selected.add(package_id)
        for dependency in nodes[package_id]["deps"]:
            visit(dependency["pkg"])

    visit(metadata["resolve"]["root"])
    ordered = sorted((packages[i] for i in selected if packages[i]["source"]), key=lambda p: (p["name"], p["version"]))
    header = """SIDE FEATHER — THIRD-PARTY LICENSES AND ATTRIBUTIONS

Side Feather itself is MIT licensed; see the separate LICENSE file.
This conservative inventory includes resolved macOS build dependencies as well
as the runtime dependency graph. Inclusion does not mean every component is
embedded in the distributed binary. System frameworks are not redistributed.
Original license/copyright/notice files from the exact Cargo registry packages
are reproduced below. Multiple offered licenses remain offered by their owners.
For packages offering MIT but omitting a standalone license file, the published
license declaration and author attribution are preserved and the standard MIT
grant/warranty terms are reproduced. Full original declarations are linked.
The Rust Standard Library's toolchain-provided copyright inventory follows.
No Adobe SDK archive, Adobe executable, or Apple SDK is redistributed.

"""
    parts = [header]
    inventory = []
    for package in ordered:
        directory = Path(package["manifest_path"]).parent
        name, version = package["name"], package["version"]
        files = sorted(p for p in directory.iterdir() if p.is_file() and re.match(r"(?i)(licen[cs]e|copying|copyright|notice|unlicense)", p.name))
        authors = [re.sub(r"\s*<[^>]*>", "", author) for author in package["authors"]]
        item = {
            "name": name, "version": version, "declaredLicense": package["license"],
            "source": f"https://crates.io/crates/{name}/{version}",
            "repository": package["repository"], "authors": authors,
            "originalNoticeFiles": [p.name for p in files],
        }
        parts.append("\n" + "=" * 78 + f"\n{name} {version}\n")
        parts.append(f"Declared license: {package['license']}\nSource: {item['source']}\n")
        if authors:
            parts.append("Published author attribution: " + "; ".join(authors) + "\n")
        if files:
            for file in files:
                parts.append(f"\n--- {file.name} (original package notice) ---\n")
                parts.append(file.read_text(errors="replace") + "\n")
        else:
            if "MIT" not in (package["license"] or ""):
                raise SystemExit(f"Missing upstream license text for {name}; do not package.")
            parts.append("\nThis release selects the MIT option declared by the package.\n")
            parts.append("The registry package omits a standalone license file.\n")
            parts.append(MIT_TERMS)
            # objc2's upstream explains its declarations; preserve the exact
            # repository statement at the package's pinned VCS revision too.
            vcs_file = directory / ".cargo_vcs_info.json"
            if package["repository"] == "https://github.com/madsmtm/objc2" and vcs_file.exists():
                revision = json.loads(vcs_file.read_text())["git"]["sha1"]
                url = f"https://raw.githubusercontent.com/madsmtm/objc2/{revision}/LICENSE.md"
                request = urllib.request.Request(url, headers={"User-Agent": "SideFeatherReleasePackager/1"})
                with urllib.request.urlopen(request, timeout=30) as response:
                    statement = response.read().decode("utf-8")
                parts.append(f"\n--- Upstream license declaration ({revision}) ---\n{url}\n{statement}\n")
                item["upstreamDeclaration"] = url
        inventory.append(item)
    sysroot = Path(subprocess.check_output(["rustc", "--print", "sysroot"], text=True).strip())
    rust_notice = sysroot / "share/doc/rust/COPYRIGHT-library.html"
    if not rust_notice.exists():
        raise SystemExit("Rust toolchain standard-library notices are required.")
    parser = PlainText()
    parser.feed(rust_notice.read_text())
    parts.append("\n" + "=" * 78 + "\nRust Standard Library — original toolchain notices\n")
    parts.append("".join(parser.parts))
    output.mkdir(parents=True, exist_ok=True)
    (output / "THIRD_PARTY_LICENSES.txt").write_text("".join(parts))
    shutil.copyfile(rust_notice, output / "RUST_STANDARD_LIBRARY_COPYRIGHT.html")
    (output / "DEPENDENCY_LICENSE_INVENTORY.json").write_text(json.dumps({
        "scope": "Conservative resolved macOS dependency graph, including build-time components",
        "cargoLockSha256": digest(source / "Cargo.lock"),
        "rustToolchain": subprocess.check_output(["rustc", "--version"], text=True).strip(),
        "dependencies": inventory,
    }, indent=2) + "\n")
    audit(output)
    print(f"Generated full notices for {len(inventory)} resolved macOS packages and Rust standard library.")


INSTALL_GUIDE = """SIDE FEATHER — INSTALLATION

For Adobe Premiere on macOS. This beta includes Intel and Apple Silicon code.
See README.md and the release notes for the exact tested host configuration.

INSTALL
1. Save your work and quit Premiere.
2. Open Install Side Feather.app and click Install Side Feather.
3. Reopen Premiere. Search the Effects panel for Side Feather.
4. Drag it onto a video clip, then adjust one side in Effect Controls.

No administrator password or Adobe account is required by the installer.
It installs only for the current macOS account. Existing recognized copies
are kept in dated backups. The installer does not open or alter your projects.

REMOVE
Save your work and quit Premiere. Open Install Side Feather.app and choose
Remove Side Feather, then confirm. The plug-in moves to a dated backup.
Projects and source media remain untouched. A project using this effect will
need the plug-in installed to reproduce its feathering.

MANUAL INSTALLATION
The Manual Install folder contains the same signed plug-in. In Finder choose
Go > Go to Folder, paste the following path, and create missing folders:
~/Library/Application Support/Adobe/Common/Plug-ins/7.0/MediaCore/
Copy Side Feather.plugin into that folder, then restart Premiere.
Avoid keeping duplicate copies in user and system plug-in directories.

BACKUPS
~/Library/Application Support/Side Feather/Backups/

CODE SIGNING AND SUPPORT
This beta is Developer ID signed and has not been notarized by Apple. macOS
may require review in System Settings > Privacy & Security before it will open.
Read README.md for the download policy and exact steps. Do not disable
Gatekeeper or remove quarantine attributes. Report unexpected messages through
the support link.

Source, releases, issue reports and current documentation:
https://github.com/mathewharwich/side-feather

Side Feather is independent software; Adobe does not provide its support.
"""


def package(args):
    plugin, installer, docs, licenses, output = map(Path, [args.plugin, args.installer, args.docs_root, args.licenses, args.output])
    for name in DOCS:
        if not (docs / name).is_file():
            raise SystemExit(f"Required public document is missing: {name}")
    for path in [plugin, installer]:
        run("codesign", "--verify", "--deep", "--strict", "--verbose=2", str(path))
    stage = output / f"SideFeather-{args.version}"
    if stage.exists():
        raise SystemExit("Output staging folder already exists; choose a fresh output directory.")
    stage.mkdir(parents=True)
    for name in DOCS:
        (stage / name).parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(docs / name, stage / name)
    for name in ["THIRD_PARTY_LICENSES.txt", "RUST_STANDARD_LIBRARY_COPYRIGHT.html", "DEPENDENCY_LICENSE_INVENTORY.json"]:
        shutil.copyfile(licenses / name, stage / name)
    (stage / "Read Me.txt").write_text(INSTALL_GUIDE)
    run("ditto", "--norsrc", "--noextattr", str(installer), str(stage / installer.name))
    manual = stage / "Manual Install"
    manual.mkdir()
    run("ditto", "--norsrc", "--noextattr", str(plugin), str(manual / plugin.name))
    if args.build_manifest:
        shutil.copyfile(args.build_manifest, stage / "BUILD_MANIFEST.json")
    count = audit(stage)
    filename = f"SideFeather-{args.version}-macOS"
    dmg = output / f"{filename}.dmg"
    zipfile = output / f"{filename}.zip"
    run("hdiutil", "create", "-quiet", "-format", "UDZO", "-fs", "HFS+", "-volname", "Side Feather", "-srcfolder", str(stage), str(dmg))
    if args.sign_identity:
        run("codesign", "--force", "--timestamp", "--sign", args.sign_identity, str(dmg))
        run("codesign", "--verify", "--strict", "--verbose=2", str(dmg))
    run("ditto", "-c", "-k", "--keepParent", "--norsrc", "--noextattr", str(stage), str(zipfile))
    (output / "SHA256SUMS.txt").write_text("".join(f"{digest(p)}  {p.name}\n" for p in [dmg, zipfile]))
    print(f"Packaged {count} allowlisted files; {dmg.name}, {zipfile.name}, SHA256SUMS.txt")
    print("Notarization is a separate verified step. Regenerate checksums after stapling.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    license_parser = commands.add_parser("licenses")
    license_parser.add_argument("--source-root", required=True)
    license_parser.add_argument("--output", required=True)
    package_parser = commands.add_parser("package")
    for name in ["plugin", "installer", "docs-root", "licenses", "output"]:
        package_parser.add_argument(f"--{name}", required=True)
    package_parser.add_argument("--version", default="0.1.0-beta.1")
    package_parser.add_argument("--sign-identity", default=os.environ.get("SIDE_FEATHER_SIGN_IDENTITY"))
    package_parser.add_argument("--build-manifest")
    args = parser.parse_args()
    if args.command == "licenses":
        generate_licenses(Path(args.source_root), Path(args.output))
    else:
        package(args)


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Coordinated, immutable Abyss/abyss_raw releases (Python standard library only)."""

import argparse
import hashlib
import io
import json
import os
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys
import tarfile
import urllib.error
import urllib.request


PACKAGES = {"abyss": ".", "abyss_raw": "packages/abyss_raw"}
STATE_MARKER = "<!-- coordinated-release-state\n"


def run(args, cwd=None, data=None):
    try:
        return subprocess.run(args, cwd=cwd, input=data, check=True, stdout=subprocess.PIPE).stdout
    except subprocess.CalledProcessError as error:
        if error.stdout:
            sys.stderr.write(error.stdout.decode(errors="replace"))
        raise


def git(root, *args):
    return run(["git", *args], cwd=root).decode().strip()


def digest(data):
    return hashlib.sha256(data).hexdigest()


def check(root, version, committed=False):
    if not re.fullmatch(r"\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?", version):
        raise ValueError("release-version must be a bare semantic version (no v prefix)")
    discovered = {p.parent.name for p in (root / "packages").glob("*/mix.exs")}
    if discovered != {"abyss_raw"}:
        raise ValueError(f"unexpected distributable package set: {sorted(discovered)}")
    for name, directory in PACKAGES.items():
        path = (Path(directory) / "mix.exs").as_posix()
        source = (root / path).read_text()
        versions = re.findall(r'@version\s+"([^"]+)"', source)
        configured = re.findall(r'version:\s*(?:"([^"]+)"|(@version))', source)
        effective = [literal or (versions[0] if len(versions) == 1 else None)
                     for literal, attribute in configured]
        if (effective != [version] or (name == "abyss" and versions != [version])
                or not re.search(rf"app:\s*:{name}\b", source)):
            raise ValueError(f"{path}: expected app {name} and self-contained version {version}")
        if committed and git(root, "show", f"HEAD:{path}") != source.strip():
            raise ValueError(f"{path}: release version must already be committed")
    return git(root, "rev-parse", "HEAD")


def archive_info(path, name, version, root=None, commit=None):
    """Validate Hex checksums; compare source, ignoring tar/gzip timestamps only."""
    with tarfile.open(path, "r:") as outer:
        if {m.name for m in outer} != {"VERSION", "CHECKSUM", "metadata.config", "contents.tar.gz"}:
            raise ValueError(f"{path}: unexpected Hex archive members")
        parts = {key: outer.extractfile(key).read() for key in
                 ("VERSION", "CHECKSUM", "metadata.config", "contents.tar.gz")}
    expected = digest(parts["VERSION"] + parts["metadata.config"] + parts["contents.tar.gz"])
    if parts["VERSION"] != b"3" or parts["CHECKSUM"].decode().strip().lower() != expected:
        raise ValueError(f"{path}: invalid Hex internal checksum")
    metadata = parts["metadata.config"]
    for key, value in (("name", name), ("version", version)):
        if not re.search(rb'\{<<"' + key.encode() + rb'">>,\s*<<"' + re.escape(value.encode()) + rb'">>\}', metadata):
            raise ValueError(f"{path}: wrong {key}, expected {value}")
    entries = []
    seen = set()
    with tarfile.open(fileobj=io.BytesIO(parts["contents.tar.gz"]), mode="r:gz") as inner:
        for member in inner:
            member_path = PurePosixPath(member.name)
            if member_path.is_absolute() or ".." in member_path.parts or member.name in seen:
                raise ValueError(f"{path}: unsafe/duplicate member {member.name}")
            seen.add(member.name)
            if member.isdir():
                continue
            if not member.isfile():
                raise ValueError(f"{path}: non-file member {member.name}")
            content = inner.extractfile(member).read()
            if root is not None:
                source = (PurePosixPath(PACKAGES[name]) / member_path).as_posix()
                committed = run(["git", "show", f"{commit}:{source}"], cwd=root)
                if content != committed:
                    raise ValueError(f"{path}: source differs from {commit}:{source}")
            entries.append([member.name, member.mode & 0o111, digest(content)])
    if not entries or "mix.exs" not in seen:
        raise ValueError(f"{path}: missing package sources")
    identity = digest(metadata + json.dumps(sorted(entries), separators=(",", ":")).encode())
    return {"name": name, "path": PACKAGES[name], "artifact": path.name,
            "sha256": digest(path.read_bytes()), "content_sha256": identity}


def write_manifest(directory, version, commit, packages):
    manifest = {"schema": 1, "version": version, "commit": commit, "packages": packages}
    (directory / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    sums = [(p["artifact"], p["sha256"]) for p in packages]
    sums.append(("manifest.json", digest((directory / "manifest.json").read_bytes())))
    (directory / "SHA256SUMS").write_text("".join(f"{sha}  {file}\n" for file, sha in sums))
    return manifest


def build(root, directory, version):
    commit = check(root, version, committed=True)
    directory.mkdir(parents=True, exist_ok=True)
    packages = []
    for name, relative in PACKAGES.items():
        archive = directory / f"{name}-{version}.tar"
        run(["mix", "hex.build", "--output", str(archive)], cwd=root / relative)
        packages.append(archive_info(archive, name, version, root, commit))
    return write_manifest(directory, version, commit, packages)


class Services:
    def __init__(self, root, directory, version):
        self.root, self.directory, self.version = root, directory, version
        self.repo = os.environ["GITHUB_REPOSITORY"]
        self.key = os.environ.get("HEX_API_KEY")
        if not self.key:
            raise ValueError("HEX_API_KEY is unavailable; no publication attempted")

    def gh(self, endpoint, method="GET", payload=None, raw=False):
        args = ["gh", "api", f"repos/{self.repo}/{endpoint}", "--method", method]
        data = None
        if payload is not None:
            args.extend(["--input", "-"])
            data = json.dumps(payload).encode()
        if raw:
            args.extend(["-H", "Accept: application/octet-stream"])
        try:
            result = run(args, data=data)
        except subprocess.CalledProcessError as error:
            # gh writes diagnostic stderr, including status; query errors must not
            # turn authentication/network failures into "not published".
            try:
                if str(json.loads(error.stdout).get("status")) == "404":
                    return None
            except (ValueError, AttributeError):
                pass
            raise
        return result if raw else json.loads(result)

    def ensure_tag(self, commit):
        reference = self.gh(f"git/ref/tags/{self.version}")
        if reference is None:
            self.gh("git/refs", "POST", {"ref": f"refs/tags/{self.version}", "sha": commit})
            reference = self.gh(f"git/ref/tags/{self.version}")
        obj = reference["object"]
        for _ in range(8):
            if obj["type"] != "tag":
                break
            obj = self.gh(f"git/tags/{obj['sha']}")["object"]
        if obj["type"] != "commit" or obj["sha"] != commit:
            raise ValueError(f"tag {self.version} conflicts with selected checkout {commit}; never move it")

    def release(self, commit):
        release = self.gh(f"releases/tags/{self.version}")
        if release is None:
            release = self.gh("releases", "POST", {"tag_name": self.version,
                "target_commitish": commit, "name": f"{self.version} (INCOMPLETE)",
                "prerelease": True, "body": "Coordinated release INCOMPLETE; publication pending."})
        if release.get("draft"):
            raise ValueError("existing release is a draft; resolve it before retrying")
        return release

    def asset(self, asset):
        return self.gh(f"releases/assets/{asset['id']}", raw=True)

    def upload(self, path):
        run(["gh", "release", "upload", self.version, str(path), "--repo", self.repo])

    def status(self, release, state, complete=False):
        status = "COMPLETE" if complete else "INCOMPLETE"
        notes = self.root / "docs" / "releases" / f"{self.version}.md"
        description = notes.read_text().strip() + "\n\n" if notes.is_file() else ""
        table = "| Package | Hex upload | Documentation | Verification |\n| --- | --- | --- | --- |\n"
        for name in PACKAGES:
            package = state["packages"][name]
            table += f"| `{name}` | {package['upload']} | {package['docs']} | {package['verification']} |\n"
        body = (description + f"Coordinated release **{status}**.\n\n"
                f"Selected commit: `{state['commit']}`. Both package versions: `{self.version}`.\n\n"
                "Artifacts are immutable. Retry this version only at the same commit. "
                "Conflicts require a new shared version; never replace an upload or move the tag.\n\n"
                + table + "\n" + STATE_MARKER + json.dumps(state, indent=2) + "\n-->")
        self.gh(f"releases/{release['id']}", "PATCH", {"body": body,
            "name": self.version if complete else f"{self.version} (INCOMPLETE)",
            "prerelease": not complete})

    def hex_archive(self, name):
        url = f"https://repo.hex.pm/tarballs/{name}-{self.version}.tar"
        try:
            with urllib.request.urlopen(url, timeout=60) as response:
                return response.read()
        except urllib.error.HTTPError as error:
            if error.code != 404:
                raise
        # A CDN 404 alone cannot prove absence (propagation can lag).
        url = f"https://hex.pm/api/packages/{name}/releases/{self.version}"
        try:
            with urllib.request.urlopen(url, timeout=60):
                raise ValueError(f"{name}: Hex API has version but CDN archive is missing; retry later")
        except urllib.error.HTTPError as error:
            if error.code == 404:
                return None
            raise

    def publish_package(self, name, path):
        # Publish the authoritative artifact, not a second mix rebuild. No replace.
        request = urllib.request.Request(f"https://hex.pm/api/packages/{name}/releases?replace=false", data=path.read_bytes(),
            headers={"Authorization": self.key, "Content-Type": "application/octet-stream",
                     "User-Agent": "abyss-coordinated-release"}, method="POST")
        try:
            with urllib.request.urlopen(request, timeout=120) as response:
                response.read()
        except urllib.error.HTTPError as error:
            raise ValueError(f"{name}: Hex upload failed (HTTP {error.code}); no replacement attempted") from None

    def publish_docs(self, name):
        run(["mix", "hex.publish", "docs", "--yes"], cwd=self.root / PACKAGES[name])

    def verify_consumers(self):
        subprocess.run(["python3", "scripts/release/verify_consumers.py", "--version", self.version,
                        "--artifacts", str(self.directory), "--published", "--legacy", "--wire",
                        "--output", str(self.directory / "consumers.json")], cwd=self.root, check=True)


def published_match(directory, package, content, root, commit, version):
    path = directory / f"hex-{package['artifact']}"
    path.write_bytes(content)
    try:
        actual = archive_info(path, package["name"], version, root, commit)
        if actual["content_sha256"] != package["content_sha256"]:
            raise ValueError(f"{package['name']}: existing Hex contents conflict; use a new shared version")
        if actual["sha256"] != package["sha256"]:
            raise ValueError(f"{package['name']}: Hex bytes differ from authoritative GitHub artifact; use a new shared version")
        return actual["sha256"]
    finally:
        path.unlink(missing_ok=True)


def publish(root, directory, version, services=None):
    commit = check(root, version, committed=True)
    services = services or Services(root, directory, version)
    # Validate local artifacts before any remote mutation.
    candidates = [archive_info(directory / f"{n}-{version}.tar", n, version, root, commit)
                  for n in PACKAGES]
    services.ensure_tag(commit)
    release = services.release(commit)
    state = {"version": version, "commit": commit, "status": "incomplete",
             "packages": {n: {"upload": "pending", "docs": "pending", "verification": "pending"}
                          for n in PACKAGES}}
    body = release.get("body") or ""
    if STATE_MARKER in body:
        old = json.loads(body.split(STATE_MARKER, 1)[1].split("\n-->", 1)[0])
        if old["commit"] != commit or old["version"] != version:
            raise ValueError("release state conflicts with selected checkout/version")
        state = old
        state["status"] = "incomplete"
        state.pop("error", None)
    try:
        services.status(release, state)
        assets = {a["name"]: a for a in release.get("assets", [])}
        old_manifest = None
        if "manifest.json" in assets:
            old_manifest = json.loads(services.asset(assets["manifest.json"]))
            if (old_manifest.get("commit"), old_manifest.get("version")) != (commit, version):
                raise ValueError("attached manifest conflicts with selected checkout/version")
            if [p["name"] for p in old_manifest["packages"]] != list(PACKAGES):
                raise ValueError("attached manifest has an unexpected package set")
        # Recover partially attached assets without replacing any. Attached bytes
        # are authoritative; rebuilt candidates may differ only in timestamps.
        for index, package in enumerate(candidates):
            path = directory / package["artifact"]
            if package["artifact"] in assets:
                attached = services.asset(assets[package["artifact"]])
                saved = directory / f"attached-{package['artifact']}"
                saved.write_bytes(attached)
                try:
                    actual = archive_info(saved, package["name"], version, root, commit)
                    if actual["content_sha256"] != package["content_sha256"]:
                        raise ValueError(f"{package['name']}: attached contents conflict with build")
                finally:
                    saved.unlink(missing_ok=True)
                path.write_bytes(attached)
                package = archive_info(path, package["name"], version, root, commit)
                candidates[index] = package
            elif old_manifest is not None:
                raise ValueError(f"{package['artifact']}: immutable release artifact is missing")
            else:
                services.upload(path)
            if old_manifest is not None and old_manifest["packages"][index] != package:
                raise ValueError(f"{package['name']}: attached artifact differs from manifest")
        manifest = write_manifest(directory, version, commit, candidates)
        if old_manifest is not None and old_manifest != manifest:
            raise ValueError("immutable manifest conflicts")
        for filename in ("manifest.json", "SHA256SUMS"):
            path = directory / filename
            if filename in assets:
                if services.asset(assets[filename]) != path.read_bytes():
                    raise ValueError(f"attached {filename} conflicts; never overwrite it")
            else:
                services.upload(path)
        # Check BOTH packages for conflicts before uploading either.
        existing = {}
        for package in candidates:
            content = services.hex_archive(package["name"])
            if content is not None:
                existing[package["name"]] = published_match(directory, package, content, root, commit, version)
        for package in candidates:
            name = package["name"]
            status = state["packages"][name]
            if name not in existing:
                if status["upload"] == "verified":
                    raise ValueError(f"{name}: previously uploaded version is missing; never republish")
                status["upload"] = "submitting"
                services.status(release, state)
                services.publish_package(name, directory / package["artifact"])
                status["upload"] = "submitted"
                services.status(release, state)
                content = services.hex_archive(name)
                if content is None:
                    raise ValueError(f"{name}: upload submitted but archive unavailable; retry later")
                existing[name] = published_match(directory, package, content, root, commit, version)
            status.update(upload="verified", hex_sha256=existing[name])
            services.status(release, state)
        for name in PACKAGES:
            if state["packages"][name]["docs"] != "published":
                services.publish_docs(name)
                state["packages"][name]["docs"] = "published"
                services.status(release, state)
        services.verify_consumers()
        for name in PACKAGES:
            state["packages"][name]["verification"] = "passed"
        state["status"] = "complete"
        services.status(release, state, complete=True)
    except Exception as error:
        state["status"] = "incomplete"
        # Keep credentials/HTTP response bodies out of the public release state.
        state["error"] = type(error).__name__ + "; inspect the workflow log and retry at the same commit"
        services.status(release, state)
        raise


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["check", "build", "publish"])
    parser.add_argument("--version", required=True)
    parser.add_argument("--artifacts", type=Path, default=Path("release-artifacts"))
    parser.add_argument("--committed", action="store_true")
    args = parser.parse_args()
    root = Path(git(Path.cwd(), "rev-parse", "--show-toplevel"))
    directory = args.artifacts.resolve()
    if args.command == "check":
        print(check(root, args.version, args.committed))
    elif args.command == "build":
        print(json.dumps(build(root, directory, args.version), indent=2))
    else:
        publish(root, directory, args.version)


if __name__ == "__main__":
    try:
        main()
    except (ValueError, subprocess.CalledProcessError, urllib.error.URLError) as error:
        print(f"Release failed: {error}", file=sys.stderr)
        sys.exit(1)

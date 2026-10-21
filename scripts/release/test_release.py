"""Offline release gates: no GitHub/Hex credentials or publication required."""

import copy
import gzip
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import tarfile
import tempfile
import unittest
from unittest.mock import MagicMock, patch


SPEC = importlib.util.spec_from_file_location("release", Path(__file__).with_name("release.py"))
release = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(release)
VERSION = "0.9.0"


def make_archive(path, name, files, timestamp=0):
    source = io.BytesIO()
    with tarfile.open(fileobj=source, mode="w") as inner:
        for filename, content in files.items():
            member = tarfile.TarInfo(filename)
            member.size, member.mode, member.mtime = len(content), 0o644, timestamp
            inner.addfile(member, io.BytesIO(content))
    contents = gzip.compress(source.getvalue(), mtime=timestamp)
    metadata = f'{{<<"name">>,<<"{name}">>}}.\n{{<<"version">>,<<"{VERSION}">>}}.\n'.encode()
    checksum = hashlib.sha256(b"3" + metadata + contents).hexdigest().upper().encode()
    with tarfile.open(path, "w") as outer:
        for filename, content in {"VERSION": b"3", "CHECKSUM": checksum,
                                  "metadata.config": metadata, "contents.tar.gz": contents}.items():
            member = tarfile.TarInfo(filename)
            member.size, member.mtime = len(content), timestamp
            outer.addfile(member, io.BytesIO(content))


class FakeServices:
    def __init__(self):
        self.remote = {"id": 1, "body": "", "assets": []}
        self.assets, self.hex, self.uploads, self.docs = {}, {}, [], []
        self.tag, self.fail_docs, self.verify_count = None, None, 0
        self.fail_upload, self.fail_after_upload, self.fail_verify = None, None, False
        self.statuses = []

    def ensure_tag(self, commit):
        if self.tag is not None and self.tag != commit:
            raise ValueError("tag conflict")
        self.tag = commit

    def release(self, commit):
        return copy.deepcopy(self.remote)

    def asset(self, asset):
        return self.assets[asset["name"]]

    def upload(self, path):
        if path.name in self.assets:
            raise AssertionError("attempted artifact replacement")
        self.assets[path.name] = path.read_bytes()
        self.remote["assets"].append({"name": path.name})

    def status(self, remote, state, complete=False):
        self.statuses.append(copy.deepcopy(state))
        self.remote["body"] = release.STATE_MARKER + json.dumps(state) + "\n-->"
        self.complete = complete

    def hex_archive(self, name):
        return self.hex.get(name)

    def publish_package(self, name, path):
        if name in self.hex:
            raise AssertionError("attempted duplicate Hex upload")
        if self.fail_upload == name:
            raise RuntimeError("simulated Hex outage")
        self.uploads.append(name)
        self.hex[name] = path.read_bytes()
        if self.fail_after_upload == name:
            raise RuntimeError("simulated lost upload response")

    def publish_docs(self, name):
        if self.fail_docs == name:
            raise RuntimeError("simulated docs outage")
        self.docs.append(name)

    def verify_consumers(self):
        self.verify_count += 1
        if self.fail_verify:
            raise RuntimeError("simulated consumer failure")


class ReleaseTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.artifacts = self.root / "artifacts"
        self.artifacts.mkdir()
        self.files = {}
        for name, directory in release.PACKAGES.items():
            location = self.root / directory
            location.mkdir(parents=True, exist_ok=True)
            mix = (f'defmodule Project do\n @version "{VERSION}"\n def project, do: [app: :{name}, version: @version]\nend\n'
                   if name == "abyss" else
                   f'defmodule Project do\n def project, do: [app: :{name}, version: "{VERSION}"]\nend\n').encode()
            self.files[name] = {"mix.exs": mix, "lib/source.ex": b"# source\n"}
            for filename, content in self.files[name].items():
                target = location / filename
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(content)
            make_archive(self.artifacts / f"{name}-{VERSION}.tar", name, self.files[name])
        subprocess.run(["git", "init", "-q", str(self.root)], check=True)
        self.git("config", "user.email", "release-test@example.invalid")
        self.git("config", "user.name", "Release test")
        self.git("add", "mix.exs", "lib", "packages")
        self.git("commit", "-qm", "fixture")
        self.commit = self.git("rev-parse", "HEAD")
        self.services = FakeServices()

    def git(self, *args):
        return subprocess.check_output(["git", *args], cwd=self.root).decode().strip()

    def publish(self):
        release.publish(self.root, self.artifacts, VERSION, self.services)

    def test_committed_shared_versions_and_package_set(self):
        self.assertEqual(release.check(self.root, VERSION, True), self.commit)
        with self.assertRaisesRegex(ValueError, "bare semantic"):
            release.check(self.root, "v" + VERSION)
        with self.assertRaisesRegex(ValueError, "self-contained"):
            release.check(self.root, "0.9.1")
        extra = self.root / "packages/unexpected/mix.exs"
        extra.parent.mkdir()
        extra.write_text("unexpected")
        with self.assertRaisesRegex(ValueError, "package set"):
            release.check(self.root, VERSION)

    def test_uncommitted_version_refused(self):
        path = self.root / "mix.exs"
        path.write_text(path.read_text() + "# changed\n")
        with self.assertRaisesRegex(ValueError, "already be committed"):
            release.check(self.root, VERSION, True)

    def test_selected_checkout_sha_used_for_tag(self):
        with patch.dict("os.environ", {"GITHUB_SHA": "wrong-workflow-sha"}):
            self.publish()
        self.assertEqual(self.services.tag, self.commit)
        self.assertEqual(self.services.uploads, ["abyss", "abyss_raw"])
        self.assertEqual(self.services.docs, ["abyss", "abyss_raw"])
        self.assertTrue(self.services.complete)

    def test_retry_preserves_uploads_docs_and_authoritative_bytes(self):
        self.services.fail_docs = "abyss_raw"
        with self.assertRaisesRegex(RuntimeError, "docs outage"):
            self.publish()
        self.assertFalse(self.services.complete)
        original = self.services.assets[f"abyss-{VERSION}.tar"]
        make_archive(self.artifacts / f"abyss-{VERSION}.tar", "abyss", self.files["abyss"], timestamp=123)
        self.assertNotEqual(original, (self.artifacts / f"abyss-{VERSION}.tar").read_bytes())
        self.services.fail_docs = None
        self.publish()
        self.assertEqual(self.services.uploads, ["abyss", "abyss_raw"])
        self.assertEqual(self.services.docs, ["abyss", "abyss_raw"])
        self.assertEqual((self.artifacts / f"abyss-{VERSION}.tar").read_bytes(), original)
        self.assertTrue(self.services.complete)

    def test_partial_asset_upload_recovers_without_overwrite(self):
        path = self.artifacts / f"abyss-{VERSION}.tar"
        self.services.upload(path)
        original = path.read_bytes()
        make_archive(path, "abyss", self.files["abyss"], timestamp=123)
        self.publish()
        self.assertEqual(path.read_bytes(), original)
        self.assertEqual(len(self.services.assets), 4)

    def test_partial_hex_upload_retry_only_publishes_missing_raw(self):
        self.services.fail_upload = "abyss_raw"
        with self.assertRaisesRegex(RuntimeError, "Hex outage"):
            self.publish()
        self.assertEqual(self.services.uploads, ["abyss"])
        self.assertEqual(self.services.statuses[-1]["packages"]["abyss"]["upload"], "verified")
        self.assertEqual(self.services.statuses[-1]["packages"]["abyss_raw"]["upload"], "submitting")
        self.assertFalse(self.services.complete)
        self.services.fail_upload = None
        self.publish()
        self.assertEqual(self.services.uploads, ["abyss", "abyss_raw"])
        self.assertTrue(self.services.complete)

    def test_uncertain_submission_is_verified_before_retry_skip(self):
        self.services.fail_after_upload = "abyss"
        with self.assertRaisesRegex(RuntimeError, "lost upload response"):
            self.publish()
        self.assertEqual(self.services.uploads, ["abyss"])
        self.services.fail_after_upload = None
        self.publish()
        self.assertEqual(self.services.uploads, ["abyss", "abyss_raw"])

    def test_consumer_failure_stays_incomplete_and_retry_verifies_again(self):
        self.services.fail_verify = True
        with self.assertRaisesRegex(RuntimeError, "consumer failure"):
            self.publish()
        self.assertFalse(self.services.complete)
        self.assertTrue(all(p["verification"] == "pending"
                            for p in self.services.statuses[-1]["packages"].values()))
        self.services.fail_verify = False
        self.publish()
        self.assertEqual(self.services.uploads, ["abyss", "abyss_raw"])
        self.assertEqual(self.services.docs, ["abyss", "abyss_raw"])
        self.assertEqual(self.services.verify_count, 2)
        self.assertTrue(self.services.complete)

    def test_existing_hex_contents_conflict_before_any_upload(self):
        foreign = self.artifacts / "foreign.tar"
        make_archive(foreign, "abyss_raw", {"mix.exs": self.files["abyss_raw"]["mix.exs"],
                                           "lib/source.ex": b"# foreign\n"})
        self.services.hex["abyss_raw"] = foreign.read_bytes()
        with self.assertRaisesRegex(ValueError, "source differs"):
            self.publish()
        self.assertEqual(self.services.uploads, [])
        self.assertFalse(self.services.complete)

    def test_existing_hex_outer_byte_conflict(self):
        for name in release.PACKAGES:
            path = self.artifacts / "existing.tar"
            make_archive(path, name, self.files[name], timestamp=456)
            self.services.hex[name] = path.read_bytes()
        with self.assertRaisesRegex(ValueError, "Hex bytes differ"):
            self.publish()
        self.assertEqual(self.services.uploads, [])
        self.assertFalse(self.services.complete)

    def test_existing_matching_hex_uploads_are_verified_and_skipped(self):
        for name in release.PACKAGES:
            self.services.hex[name] = (self.artifacts / f"{name}-{VERSION}.tar").read_bytes()
        self.publish()
        self.assertEqual(self.services.uploads, [])
        self.assertTrue(self.services.complete)

    def test_missing_local_artifact_does_not_create_tag(self):
        (self.artifacts / f"abyss_raw-{VERSION}.tar").unlink()
        with self.assertRaises(FileNotFoundError):
            self.publish()
        self.assertIsNone(self.services.tag)

    def test_missing_persisted_artifact_aborts(self):
        self.publish()
        self.services.remote["assets"] = [a for a in self.services.remote["assets"]
                                          if a["name"] != f"abyss_raw-{VERSION}.tar"]
        with self.assertRaisesRegex(ValueError, "artifact is missing"):
            self.publish()
        self.assertEqual(self.services.uploads, ["abyss", "abyss_raw"])

    def test_tag_conflict_aborts(self):
        self.services.tag = "other-commit"
        with self.assertRaisesRegex(ValueError, "tag conflict"):
            self.publish()
        self.assertFalse(self.services.assets)

    def test_checksum_corruption_refused(self):
        path = self.artifacts / f"abyss-{VERSION}.tar"
        path.write_bytes(path.read_bytes().replace(b"3", b"4", 1))
        with self.assertRaises((ValueError, tarfile.ReadError)):
            release.archive_info(path, "abyss", VERSION)

    def test_remote_tag_uses_selected_commit(self):
        service = object.__new__(release.Services)
        service.version = VERSION
        calls = []

        def gh(endpoint, method="GET", payload=None):
            calls.append((endpoint, method, payload))
            if endpoint == f"git/ref/tags/{VERSION}":
                return None if len(calls) == 1 else {"object": {"type": "commit", "sha": self.commit}}
            return {}

        service.gh = gh
        service.ensure_tag(self.commit)
        self.assertEqual(calls[1][2], {"ref": f"refs/tags/{VERSION}", "sha": self.commit})

    def test_remote_annotated_tag_is_peeled_and_conflicts_refused(self):
        service = object.__new__(release.Services)
        service.version = VERSION
        service.gh = lambda endpoint: ({"object": {"type": "tag", "sha": "tag-object"}}
            if endpoint.startswith("git/ref/") else {"object": {"type": "commit", "sha": "conflict"}})
        with self.assertRaisesRegex(ValueError, "never move"):
            service.ensure_tag(self.commit)

    def test_hex_publishes_authoritative_tar_to_nonreplace_package_endpoint(self):
        service = object.__new__(release.Services)
        service.key = "fake-test-key"
        path = self.artifacts / f"abyss-{VERSION}.tar"
        with patch.object(release.urllib.request, "urlopen", return_value=MagicMock()) as request:
            service.publish_package("abyss", path)
        actual = request.call_args.args[0]
        self.assertEqual(actual.full_url, "https://hex.pm/api/packages/abyss/releases?replace=false")
        self.assertEqual(actual.method, "POST")
        self.assertEqual(actual.data, path.read_bytes())
        self.assertEqual(actual.get_header("Authorization"), "fake-test-key")

    def test_missing_key_fails_before_any_remote_action(self):
        with patch.dict("os.environ", {"GITHUB_REPOSITORY": "test/repo"}, clear=True):
            with self.assertRaisesRegex(ValueError, "unavailable"):
                release.Services(self.root, self.artifacts, VERSION)

    def test_http_404_is_absent_but_other_failures_propagate(self):
        service = object.__new__(release.Services)
        service.repo = "test/repo"
        missing = subprocess.CalledProcessError(1, ["gh"], output=b'{"status":"404"}')
        forbidden = subprocess.CalledProcessError(1, ["gh"], output=b'{"status":"403"}')
        with patch.object(release, "run", side_effect=missing):
            self.assertIsNone(service.gh("releases/tags/0.9.0"))
        with patch.object(release, "run", side_effect=forbidden):
            with self.assertRaises(subprocess.CalledProcessError):
                service.gh("releases/tags/0.9.0")


if __name__ == "__main__":
    unittest.main()

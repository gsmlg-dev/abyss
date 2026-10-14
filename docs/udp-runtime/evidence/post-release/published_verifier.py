#!/usr/bin/env python3
"""Independently verify a published Abyss archive and fresh Hex-only UDP consumer.

Prepare: python3 published_verifier.py --version <version> --prepare
Verify:  python3 published_verifier.py --version <version> --expected-sha <tag-commit>
Run under the project's OTP 27 devenv shell; no publication or Git mutation occurs.
"""
import argparse
import hashlib
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile
import urllib.request

ROOT = Path(__file__).resolve().parents[4]
EVIDENCE = Path(__file__).resolve().parent
MIX = '''defmodule PublishedConsumer.MixProject do
  use Mix.Project
  def project, do: [app: :published_consumer, version: "0.0.0", deps: [{:abyss, "== @RELEASE_VERSION@"}]]
  def application, do: [extra_applications: [:logger]]
end
'''
SMOKE = '''defmodule PublishedLegacyEcho do
  use Abyss.Handler
  @impl true
  def handle_data({ip, port, payload}, state) do
    :ok = Abyss.Transport.UDP.send(state.socket, ip, port, payload)
    {:close, state}
  end
end

defmodule PublishedDatagramEcho do
  @behaviour Abyss.DatagramHandler
  @impl true
  def init(options, _context), do: {:ok, options}
  @impl true
  def handle_datagram(%Abyss.Datagram{peer: %{addr: ip, port: port}, payload: payload}, options)
      when is_tuple(ip) and is_integer(port) and is_binary(payload) do
    action = if options[:strict], do: {:reply, payload, :strict}, else: {:reply, payload}
    {:ok, options, [action]}
  end
end

defmodule PublishedSmoke do
  def run do
    for command <- ["cargo", "rustc", "rustup"], do: nil = System.find_executable(command)
    for module <- [AbyssDhcpSocket.Native, Rustler, ElixirQuic], do: false = Code.ensure_loaded?(module)
    forbidden = [:rustler, :abyss_dhcp_socket, :elixir_quic, :ex_ssl]
    false = Enum.any?(Map.keys(Mix.Project.deps_paths()), &(&1 in forbidden))
    false = Enum.any?(Application.loaded_applications(), fn {app, _, _} -> app in forbidden end)
    ~c"@RELEASE_VERSION@" = Application.spec(:abyss, :vsn)
    lock = Code.eval_file("mix.lock") |> elem(0)
    Enum.each(lock, fn {name, entry} ->
      :hex = elem(entry, 0)
      IO.puts("PUBLISHED_HEX_DEP #{name} #{elem(entry, 2)}")
    end)
    {:hex, :abyss, "@RELEASE_VERSION@", _, _, _, "hexpm", _} = lock[:abyss]

    for {function, arguments} <- [
          {:open, ["lo", self()]}, {:send_broadcast, [make_ref(), <<>>]},
          {:send_unicast, [make_ref(), {127, 0, 0, 1}, <<>>]},
          {:send_arp_probe, [make_ref(), {127, 0, 0, 1}]}, {:close, [make_ref()]}
        ] do
      {:error, {:missing_optional_dependency, :abyss_dhcp_socket}} =
        apply(Abyss.DhcpSocket.Native, function, arguments)
    end

    for family <- [:inet, :inet6], backend <- [:inet, :socket] do
      exchange(:legacy, family, backend, nil)
      for policy <- [:per_datagram, :endpoint, :keyed], do: exchange(:datagram, family, backend, policy)
    end
    for family <- [:inet, :inet6], do: exchange(:native_strict, family, nil, :per_datagram)
    IO.puts("PUBLISHED_CORE_HEX_ONLY_NO_RUST_NO_QUIC_PASS exchanges=54 endpoints=18")
  end

  defp exchange(mode, family, backend, policy) do
    ip = if family == :inet, do: {127, 0, 0, 1}, else: {0, 0, 0, 0, 0, 0, 0, 1}
    transport = [family, {:ip, ip}] ++ if(backend, do: [inet_backend: backend], else: [])
    opts = [port: 0, transport_options: transport]
    opts = case mode do
      :legacy -> opts ++ [handler_module: PublishedLegacyEcho, num_listeners: 1]
      _ -> opts ++ [datagram_handler: PublishedDatagramEcho, execution: policy,
                    handler_options: [strict: mode == :native_strict]]
    end
    opts = if policy == :keyed, do: opts ++ [route_key: fn datagram -> datagram.peer end], else: opts
    opts = if mode == :native_strict, do: opts ++ [io_backend: :socket_native], else: opts
    {:ok, server} = Abyss.start_link(opts)
    {:ok, {^ip, port}} = if mode == :legacy do
      [listener] = server |> Abyss.Server.listener_pool_pid() |> Abyss.ListenerPool.listener_pids()
      Abyss.Listener.listener_info_cached(listener)
    else
      Abyss.Endpoint.local_endpoint(server)
    end
    {:ok, peer} = :gen_udp.open(0, [:binary, family, {:active, false}, {:ip, ip}])
    try do
      for payload <- [<<>>, <<0, 255, 128, 1>>, "published-@RELEASE_VERSION@-udp"] do
        :ok = :gen_udp.send(peer, ip, port, payload)
        {:ok, {^ip, ^port, ^payload}} = :gen_udp.recv(peer, 0, 2000)
      end
      IO.puts("PUBLISHED_WIRE_PASS #{mode} #{family} #{backend || :native} #{policy || :legacy} packets=3")
    after
      :gen_udp.close(peer)
      :ok = Abyss.stop(server, 1000)
    end
  end
end

PublishedSmoke.run()
'''


def output(command, cwd=ROOT):
    return subprocess.check_output(command, cwd=cwd)


def download(url):
    print("DOWNLOAD", url, flush=True)
    with urllib.request.urlopen(url, timeout=60) as response:
        return response.read()


def prepare(version):
    stage = Path(tempfile.mkdtemp(prefix="abyss-published-" + version + "-"))
    consumer = stage / "consumer"
    consumer.mkdir()
    (consumer / "mix.exs").write_text(MIX.replace("@RELEASE_VERSION@", version))
    (consumer / "smoke.exs").write_text(SMOKE.replace("@RELEASE_VERSION@", version))
    no_rust = stage / "no-rust-bin"
    no_rust.mkdir()
    for name in ("elixir", "mix", "erl", "erlc", "escript", "rebar3", "sh", "bash",
                 "dirname", "readlink", "basename", "sed", "grep", "uname", "env",
                 "mkdir", "rm", "curl", "tar", "gzip", "git"):
        executable = shutil.which(name)
        if executable:
            (no_rust / name).symlink_to(executable)
    assert not any((no_rust / name).exists() for name in ("cargo", "rustc", "rustup"))
    print("PUBLISHED_STAGE=" + str(stage), flush=True)
    return stage


def verify(stage, expected, version):
    tag = json.loads(output(["gh", "api", "repos/gsmlg-dev/abyss/git/ref/tags/" + version]))
    assert tag["object"]["type"] == "commit", tag
    assert tag["object"]["sha"] == expected, tag
    (EVIDENCE / "published-tag.json").write_text(json.dumps(tag, indent=2) + "\n")
    release = json.loads(output(["gh", "api", "repos/gsmlg-dev/abyss/releases/tags/" + version]))
    assert release["tag_name"] == version, release
    assert not release["draft"] and not release["prerelease"], release
    (EVIDENCE / "published-github-release.json").write_text(json.dumps(release, indent=2) + "\n")
    metadata_bytes = download("https://hex.pm/api/packages/abyss/releases/" + version)
    metadata = json.loads(metadata_bytes)
    (EVIDENCE / "published-hex.json").write_bytes(metadata_bytes)
    assert metadata["version"] == version and metadata["meta"]["app"] == "abyss"
    requirements = metadata["requirements"]
    assert set(requirements) == {"telemetry", "telemetry_metrics", "ex_doc"}, requirements
    for name in ("telemetry", "telemetry_metrics"):
        assert requirements[name] == {"app": name, "optional": False, "requirement": "~> 1.0"}
    assert requirements["ex_doc"] == {"app": "ex_doc", "optional": False, "requirement": ">= 0.0.0"}
    archive = download("https://repo.hex.pm/tarballs/abyss-" + version + ".tar")
    (stage / ("abyss-" + version + ".tar")).write_bytes(archive)
    outer_sha = hashlib.sha256(archive).hexdigest()
    assert outer_sha == metadata["checksum"], (outer_sha, metadata["checksum"])
    with tarfile.open(fileobj=io.BytesIO(archive)) as outer:
        version_bytes = outer.extractfile("VERSION").read()
        config = outer.extractfile("metadata.config").read()
        contents = outer.extractfile("contents.tar.gz").read()
        inner_sha = hashlib.sha256(version_bytes + config + contents).hexdigest()
        assert inner_sha.upper() == outer.extractfile("CHECKSUM").read().decode().strip().upper()
    packaged = {}
    with tarfile.open(fileobj=io.BytesIO(contents), mode="r:gz") as inner:
        for member in inner.getmembers():
            assert member.isdir() or member.isfile(), member.name
            if member.isfile():
                assert member.name not in packaged, member.name
                packaged[member.name] = inner.extractfile(member).read()
    selected = {"LICENSE", "mix.exs", "README.md", "docs/dispatcher.md", "docs/quic-service.md",
                "docs/udp-broadcast-multicast.md", "docs/udp-runtime/design.md", "docs/udp-runtime/migration.md",
                "docs/README.md", "docs/architecture.md", "docs/operations.md"}
    tracked = output(["git", "ls-tree", "-r", "--name-only", expected]).decode().splitlines()
    expected_files = {name for name in tracked if name.startswith("lib/") or name in selected}
    assert set(packaged) == expected_files, (set(packaged) - expected_files, expected_files - set(packaged))
    comparisons = []
    for name, source in sorted(packaged.items()):
        assert source == output(["git", "show", expected + ":" + name]), name
        comparisons.append({"file": name, "sha256": hashlib.sha256(source).hexdigest()})
    github_archive = download(release["tarball_url"])
    (stage / ("github-" + version + ".tar.gz")).write_bytes(github_archive)
    github_sources = {}
    with tarfile.open(fileobj=io.BytesIO(github_archive), mode="r:gz") as github:
        for member in github.getmembers():
            if member.isfile():
                _, _, name = member.name.partition("/")
                if name in packaged:
                    assert name not in github_sources, name
                    github_sources[name] = github.extractfile(member).read()
    assert set(github_sources) == set(packaged), set(packaged) - set(github_sources)
    for name, source in packaged.items():
        assert github_sources[name] == source, name
    print("PUBLISHED_GITHUB_RELEASE_TAG_SOURCE_PASS", len(github_sources), release["html_url"], flush=True)
    print("PUBLISHED_ARCHIVE_CHECKSUM_DEPENDENCIES_SOURCE_PASS", len(comparisons), outer_sha, flush=True)
    environment = dict(os.environ, MIX_ENV="prod", CI="true", PATH=str(stage / "no-rust-bin"),
                       HEX_HOME=str(stage / "hex-home"), ERL_FLAGS="+S 8:8")
    for name in ("MIX_BUILD_PATH", "MIX_DEPS_PATH", "CARGO_TARGET_DIR"):
        environment.pop(name, None)
    consumer = stage / "consumer"
    for command in (["elixir", "--version"], ["mix", "deps.get"],
                    ["mix", "compile", "--warnings-as-errors"], ["mix", "run", "smoke.exs"]):
        print("COMMAND", str(consumer), command, flush=True)
        subprocess.run(command, cwd=consumer, env=environment, check=True)
    for name, source in packaged.items():
        assert (consumer / "deps/abyss" / name).read_bytes() == source, name
    artifacts = [str(path.relative_to(consumer)) for path in consumer.rglob("*")
                 if path.suffix in (".so", ".dylib", ".dll")]
    assert not artifacts, artifacts
    (EVIDENCE / "published-consumer-mix.lock").write_bytes((consumer / "mix.lock").read_bytes())
    report = {"result": "PASS", "version": version, "tag_sha": expected, "stage": str(stage),
              "github_release_url": release["html_url"], "github_archive_sha256": hashlib.sha256(github_archive).hexdigest(),
              "packaged_file_count": len(comparisons), "github_source_file_count": len(github_sources),
              "hex_archive_sha256": outer_sha, "hex_inner_sha256": inner_sha,
              "requirements": requirements, "source_files": comparisons,
              "consumer_dependency_source": "Hex only, exact abyss == " + version + ", fresh registry/build/deps",
              "wire_endpoints": 18, "actual_wire_exchanges": 54,
              "coverage": "legacy and all three Datagram policies; inet/socket; IPv4/IPv6; empty/binary/text; native strict IPv4/IPv6",
              "native_artifacts": artifacts, "optional_dhcp_package": "NOT PUBLISHED OR REBUILT"}
    (EVIDENCE / "published-verification.json").write_text(json.dumps(report, indent=2) + "\n")
    print("PUBLISHED_INDEPENDENT_VERIFICATION_PASS", version, expected, flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--version", required=True)
    parser.add_argument("--prepare", action="store_true")
    parser.add_argument("--expected-sha")
    args = parser.parse_args()
    assert args.prepare or args.expected_sha, "--expected-sha required unless --prepare"
    fresh = prepare(args.version)
    if not args.prepare:
        verify(fresh, args.expected_sha, args.version)

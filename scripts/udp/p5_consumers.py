#!/usr/bin/env python3
"""Build Hex contents into fresh opt-in consumers; never publish packages."""
import argparse
import io
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def facade(source):
    source = source.replace('Production DHCP socket implementation via Rust NIF.',
                            'Compatibility facade for the optional `abyss_dhcp_socket` package.')
    source = source.replace('Loads the `dhcp_socket` Rust crate compiled by Rustler. Provides a',
                            'Install the optional package explicitly to use this feature. Provides a')
    source = source.replace('  use Rustler,\n    otp_app: :abyss,\n    crate: "dhcp_socket"',
                            '  @implementation AbyssDhcpSocket.Native')
    source = source.replace(':: {:ok, reference()} | {:error, term()}', ':: reference() | {:error, term()}')
    for function, parameters in [('open', 'interface, owner'), ('send_broadcast', 'socket, packet'),
                                 ('send_unicast', 'socket, dest_ip, packet'),
                                 ('send_arp_probe', 'socket, target_ip'), ('close', 'socket')]:
        old = '_'+parameters.replace(', ', ', _')
        source = source.replace(f'def {function}({old}), do: :erlang.nif_error(:nif_not_loaded)',
                                f'def {function}({parameters}), do: invoke(:{function}, [{parameters}])')
    source = source.replace('@spec close(reference()) :: :ok', '@spec close(reference()) :: :ok | {:error, term()}')
    source = source.rsplit('\nend', 1)[0] + '''

  defp invoke(function, arguments) do
    case Code.ensure_loaded(@implementation) do
      {:module, @implementation} -> apply(@implementation, function, arguments)
      {:error, :nofile} -> {:error, {:missing_optional_dependency, :abyss_dhcp_socket}}
      {:error, reason} -> {:error, {:optional_dependency_load_failed, :abyss_dhcp_socket, reason}}
    end
  end
end
'''
    return source


def core_mix(source):
    source = source.replace('      {:rustler, "~> 0.34", runtime: false},\n', '')
    source = source.replace('docs/udp-broadcast-multicast.md\n           native/dhcp_socket/src native/dhcp_socket/Cargo.toml\n           native/dhcp_socket/Cargo.lock native/dhcp_socket/.cargo)',
                            'docs/udp-broadcast-multicast.md)')
    return source


def run(command, cwd, environment):
    print('COMMAND', str(cwd), command, flush=True)
    subprocess.run(command, cwd=cwd, env=environment, check=True)


def unpack(archive, destination):
    destination.mkdir()
    with tarfile.open(archive) as outer:
        contents = outer.extractfile('contents.tar.gz').read()
    with tarfile.open(fileobj=io.BytesIO(contents), mode='r:gz') as inner:
        inner.extractall(destination, filter='data')


def consumer(directory, optional):
    directory.mkdir()
    dependencies = '[{:abyss, path: "../core-package"}'
    if optional:
        dependencies += ', {:abyss_dhcp_socket, path: "../native-package"}'
    dependencies += ']'
    (directory / 'mix.exs').write_text('''defmodule P5Consumer.MixProject do
  use Mix.Project
  def project, do: [app: :p5_consumer, version: "0.0.0", deps: '''+dependencies+''']
  def application, do: [extra_applications: [:logger]]
end
''')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--staged', action='store_true', help='validate candidate before root extraction')
    args = parser.parse_args()
    stage = Path(tempfile.mkdtemp(prefix='abyss-p5-'))
    print('P5_STAGE='+str(stage), flush=True)
    environment = dict(os.environ, MIX_ENV='prod', CI='true')
    for key in ('MIX_BUILD_PATH', 'MIX_DEPS_PATH', 'CARGO_TARGET_DIR'):
        environment.pop(key, None)
    core = stage / 'core-source'
    core.mkdir()
    for name in ('mix.exs', 'mix.lock', 'LICENSE', 'README.md', 'lib', 'docs'):
        source = ROOT / name
        if source.is_dir():
            shutil.copytree(source, core / name)
        else:
            shutil.copy2(source, core / name)
    if args.staged:
        path = core / 'lib/abyss/dhcp_socket/native.ex'
        path.write_text(facade(path.read_text()))
        path = core / 'mix.exs'
        path.write_text(core_mix(path.read_text()))
    lock = (core / 'mix.lock').read_text()
    (core / 'mix.lock').write_text('\n'.join(line for line in lock.splitlines() if not line.startswith('  "rustler":'))+'\n')
    native = stage / 'native-source'
    shutil.copytree(ROOT / 'packages/abyss_dhcp_socket', native,
                    ignore=shutil.ignore_patterns('_build', 'deps', 'target', 'priv', '*.tar'))
    for source in (core, native):
        run(['mix', 'hex.build'], source, environment)
    unpack(next(core.glob('abyss-*.tar')), stage / 'core-package')
    unpack(next(native.glob('abyss_dhcp_socket-*.tar')), stage / 'native-package')
    assert not (stage / 'core-package/native').exists()
    assert not (stage / 'core-package/priv').exists()
    assert not (stage / 'core-package/packages').exists()
    no_rust = stage / 'no-rust-bin'
    no_rust.mkdir()
    for command in ('elixir', 'mix', 'erl', 'erlc', 'escript', 'rebar3', 'sh', 'bash', 'dirname',
                    'readlink', 'basename', 'sed', 'grep', 'uname', 'env', 'mkdir', 'rm', 'curl', 'tar', 'gzip', 'git'):
        executable = shutil.which(command)
        if executable:
            (no_rust / command).symlink_to(executable)
    core_environment = dict(environment, PATH=str(no_rust))
    plain = stage / 'core-consumer'
    consumer(plain, False)
    shutil.copy2(core / 'mix.lock', plain / 'mix.lock')
    run(['mix', 'deps.get'], plain, core_environment)
    run(['mix', 'compile', '--warnings-as-errors'], plain, core_environment)
    run(['mix', 'run', str(ROOT / 'scripts/udp/p5_core_consumer.exs')], plain, core_environment)
    for path in plain.rglob('*'):
        assert path.suffix not in ('.so', '.dylib', '.dll'), path
    with_native = stage / 'native-consumer'
    consumer(with_native, True)
    shutil.copy2(ROOT / 'mix.lock', with_native / 'mix.lock')
    run(['mix', 'deps.get'], with_native, environment)
    run(['mix', 'compile', '--warnings-as-errors'], with_native, environment)
    run(['mix', 'run', '-e', 'true = Code.ensure_loaded?(AbyssDhcpSocket.Native); IO.puts("P5_NATIVE_LOAD_PASS")'], with_native, environment)
    run(['python3', str(ROOT / 'scripts/udp/dhcp_fixture.py'), '--consumer', str(with_native)], ROOT, environment)
    (stage / 'PASS').write_text('packaged core no-Rust and optional native consumers passed\n')
    print('P5_PACKAGED_CONSUMERS_PASS '+str(stage), flush=True)


if __name__ == '__main__':
    main()

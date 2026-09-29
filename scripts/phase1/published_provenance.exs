# Run from either independent QUIC example with `mix run --no-start`.
deps = Mix.Dep.load_and_cache()
lock = Mix.Dep.Lock.read()

for {app, version, module, outer_checksum} <- [
      {:elixir_quic, "0.2.2", Quic,
       "2c73402421edf4156db843bbf11fe26aa5cd78eb1ae7acac863ed41fa47e8c74"},
      {:ex_ssl, "0.7.2", SSL.QUIC,
       "f0f9532a6ac8b2dcb701b491394705df8f10c31f63fc7e5aad157eebb909aecb"}
    ] do
  dep = Enum.find(deps, &(&1.app == app)) || raise("missing #{app} dependency")
  true = dep.scm == Hex.SCM
  true = dep.opts[:hex] == Atom.to_string(app)
  true = Path.expand(dep.opts[:dest]) == Path.expand("deps/#{app}")

  {:hex, ^app, ^version, _checksum, _managers, _dependencies, "hexpm", ^outer_checksum} =
    Map.fetch!(lock, app)

  true = Code.ensure_loaded?(module)
  true = to_string(Application.spec(app, :vsn)) == version
  app_dir = Path.expand(Path.join([Mix.Project.build_path(), "lib", Atom.to_string(app)]))
  true = Path.expand(Application.app_dir(app)) == app_dir
  true = Path.expand(Path.dirname(to_string(:code.which(module)))) == Path.join(app_dir, "ebin")
end

false = Code.ensure_loaded?(QUIC)
false = Map.has_key?(lock, :ex_quic)
IO.puts("PUBLISHED_QUIC_PROVENANCE_PASS elixir_quic=0.2.2 ex_ssl=0.7.2")

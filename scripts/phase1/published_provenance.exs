# Run from either independent QUIC example with `mix run --no-start`.
deps = Mix.Dep.load_and_cache()
lock = Mix.Dep.Lock.read()

for {app, version, module, outer_checksum} <- [
      {:elixir_quic, "0.17.0", Quic,
       "09bdf0ddc54da37fc5264151110c547fc5d28188b1d34961d98081d95f6d81ba"},
      {:ex_ssl, "0.17.0", SSL.QUIC,
       "253b90f7304f09402869d814cf75bd76eb2fbf34bfaf4284822c407312fae095"}
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
IO.puts("PUBLISHED_QUIC_PROVENANCE_PASS elixir_quic=0.17.0 ex_ssl=0.17.0")

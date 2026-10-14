# Run from either independent QUIC example with `mix run --no-start`.
deps = Mix.Dep.load_and_cache()
lock = Mix.Dep.Lock.read()

for {app, version, module, outer_checksum} <- [
      {:elixir_quic, "0.21.6", Quic,
       "46524b458df416964804039cc60c33ab9827e79ae67e99d21d5d5e2d7048eb75"},
      {:ex_ssl, "0.21.6", SSL.QUIC,
       "57822e99e5b8ae777108451e877ab04b5bcc4a36a3257224f9f78bc96e69ceab"}
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
IO.puts("PUBLISHED_QUIC_PROVENANCE_PASS elixir_quic=0.21.6 ex_ssl=0.21.6")

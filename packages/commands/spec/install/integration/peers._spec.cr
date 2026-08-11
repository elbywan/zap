require "./spec_helper"


# Peer dependency semantics, mirroring yarn's pkg-tests fixtures
# (fallback-peer-deps, peer-deps, provides-peer-deps, peer-deps-lvl0/1/2).
describe "peer dependencies", tags: "integration" do
  it "resolves peers from the top level" do
    It.with_registry do |registry|
      registry.add("peer-deps", "1.0.0", It.pkg("peer-deps", "1.0.0", peer_dependencies: {"no-deps" => "*"}), {"index.js" => "pd"})
      registry.add("no-deps", "1.0.0", It.pkg("no-deps", "1.0.0"), {"index.js" => "1.0.0"})

      It.install_project(
        registry,
        %({"name":"app","version":"1.0.0","dependencies":{"peer-deps":"1.0.0","no-deps":"1.0.0"}})
      ) do |project|
        File.exists?(project / "node_modules/peer-deps/index.js").should be_true
        File.read(project / "node_modules/no-deps/index.js").should eq("1.0.0")
      end
    end
  end

  it "resolves peers from within a dependency" do
    It.with_registry do |registry|
      registry.add("peer-deps", "1.0.0", It.pkg("peer-deps", "1.0.0", peer_dependencies: {"no-deps" => "*"}), {"index.js" => "pd"})
      registry.add("no-deps", "1.0.0", It.pkg("no-deps", "1.0.0"), {"index.js" => "1.0.0"})
      registry.add("provides-peer-deps", "1.0.0",
        It.pkg("provides-peer-deps", "1.0.0", dependencies: {"peer-deps" => "1.0.0", "no-deps" => "1.0.0"}),
        {"index.js" => "ppd"})

      It.install_project(registry, %({"name":"app","version":"1.0.0","dependencies":{"provides-peer-deps":"1.0.0"}})) do |project|
        File.exists?(project / "node_modules/peer-deps/index.js").should be_true
        File.read(project / "node_modules/no-deps/index.js").should eq("1.0.0")
      end
    end
  end

  it "resolves peers two levels deep" do
    It.with_registry do |registry|
      registry.add("no-deps", "1.0.0", It.pkg("no-deps", "1.0.0"), {"index.js" => "1.0.0"})
      registry.add("peer-deps-lvl0", "1.0.0",
        It.pkg("peer-deps-lvl0", "1.0.0", dependencies: {"no-deps" => "1.0.0", "peer-deps-lvl1" => "1.0.0"}),
        {"index.js" => "lvl0"})
      registry.add("peer-deps-lvl1", "1.0.0",
        It.pkg("peer-deps-lvl1", "1.0.0", dependencies: {"peer-deps-lvl2" => "1.0.0"}, peer_dependencies: {"no-deps" => "*"}),
        {"index.js" => "lvl1"})
      registry.add("peer-deps-lvl2", "1.0.0",
        It.pkg("peer-deps-lvl2", "1.0.0", peer_dependencies: {"no-deps" => "*"}),
        {"index.js" => "lvl2"})

      It.install_project(registry, %({"name":"app","version":"1.0.0","dependencies":{"peer-deps-lvl0":"1.0.0"}})) do |project|
        File.exists?(project / "node_modules/peer-deps-lvl0/index.js").should be_true
        File.exists?(project / "node_modules/peer-deps-lvl1/index.js").should be_true
        File.exists?(project / "node_modules/peer-deps-lvl2/index.js").should be_true
        File.read(project / "node_modules/no-deps/index.js").should eq("1.0.0")
      end
    end
  end

  it "prefers the peer over the same regular dependency when the peer is met" do
    It.with_registry do |registry|
      # fallback-peer-deps declares a regular dep on no-deps@2 AND a peer on no-deps@*
      registry.add("fallback-peer-deps", "1.0.0",
        It.pkg("fallback-peer-deps", "1.0.0", dependencies: {"no-deps" => "2.0.0"}, peer_dependencies: {"no-deps" => "*"}),
        {"index.js" => "fpd"})
      registry.add("no-deps", "1.0.0", It.pkg("no-deps", "1.0.0"), {"index.js" => "1.0.0"})
      registry.add("no-deps", "2.0.0", It.pkg("no-deps", "2.0.0"), {"index.js" => "2.0.0"})

      It.install_project(
        registry,
        %({"name":"app","version":"1.0.0","dependencies":{"fallback-peer-deps":"1.0.0","no-deps":"1.0.0"}})
      ) do |project|
        # The peer (from the root) wins: no-deps@2 is not installed under the package
        File.read(project / "node_modules/no-deps/index.js").should eq("1.0.0")
        File.exists?(project / "node_modules/fallback-peer-deps/node_modules/no-deps").should be_false
      end
    end
  end

  it "falls back to the regular dependency when the peer is unmet" do
    It.with_registry do |registry|
      registry.add("fallback-peer-deps", "1.0.0",
        It.pkg("fallback-peer-deps", "1.0.0", dependencies: {"no-deps" => "2.0.0"}, peer_dependencies: {"no-deps" => "*"}),
        {"index.js" => "fpd"})
      registry.add("no-deps", "2.0.0", It.pkg("no-deps", "2.0.0"), {"index.js" => "2.0.0"})

      It.install_project(registry, %({"name":"app","version":"1.0.0","dependencies":{"fallback-peer-deps":"1.0.0"}})) do |project|
        # No ancestor provides the peer, so the regular dependency is installed
        # instead and resolves from the tree (hoisted to the root here)
        File.read(project / "node_modules/no-deps/index.js").should eq("2.0.0")
      end
    end
  end

  it "marks transitive peers per providing ancestor in a diamond" do
    It.with_registry do |registry|
      registry.add("react", "1.0.0", It.pkg("react", "1.0.0"), {"index.js" => "1.0.0"})
      registry.add("widget", "1.0.0", It.pkg("widget", "1.0.0", peer_dependencies: {"react" => "*"}), {"index.js" => "w"})
      registry.add("parent-a", "1.0.0", It.pkg("parent-a", "1.0.0", dependencies: {"react" => "1.0.0", "widget" => "1.0.0"}), {"index.js" => "a"})
      registry.add("parent-b", "1.0.0", It.pkg("parent-b", "1.0.0", dependencies: {"widget" => "1.0.0"}), {"index.js" => "b"})

      tmpdir = Path.new(Dir.tempdir, "zap-it-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(tmpdir)
        File.write(tmpdir / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"parent-a":"1.0.0","parent-b":"1.0.0"}}))
        File.write(tmpdir / ".npmrc", "registry=#{registry.base_url}/\n")
        config = Core::Config.new.copy_with(prefix: tmpdir.to_s, store_path: (tmpdir / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)

        # Rebuild the state and re-resolve in-process: the dependency refs
        # the reduce walks are not persisted in the lockfile.
        inferred = config.infer_context
        state = Commands::Install::State.new(
          config: inferred.config,
          install_config: ic,
          store: ::Store.new(inferred.config.store_path),
          main_package: inferred.main_package,
          lockfile: Data::Lockfile.new(inferred.config.prefix),
          context: inferred,
          npmrc: Data::Npmrc.new(inferred.config.prefix),
          registry_clients: Commands::Install::RegistryClients.new(inferred.config.store_path, Data::Npmrc.new(inferred.config.prefix), pool_max_size: 4),
          pipeline: Concurrency::Pipeline.new(workers: 1),
          reporter: Reporter::Null.new
        )
        state.context.scope_packages(:install).each do |pkg|
          Commands::Install::Resolver.resolve_dependencies_of(pkg, state: state)
        end
        state.pipeline.await

        state.lockfile.mark_transitive_peers
        a = state.lockfile.get_package("parent-a", "1.0.0")
        b = state.lockfile.get_package("parent-b", "1.0.0")

        # parent-a depends on react: the propagated peer is resolved there.
        a.transitive_peer_dependencies.should be_nil
        # parent-b does not: the peer is unresolved below it.
        b.transitive_peer_dependencies.not_nil!["react"].should_not be_empty
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end

  it "propagates peers through cyclic dependencies (fixpoint union)" do
    It.with_registry do |registry|
      registry.add("engine", "1.0.0", It.pkg("engine", "1.0.0"), {"index.js" => "1.0.0"})
      registry.add("widget", "1.0.0", It.pkg("widget", "1.0.0", dependencies: {"helper" => "1.0.0"}), {"index.js" => "w"})
      registry.add("helper", "1.0.0", It.pkg("helper", "1.0.0", dependencies: {"widget" => "1.0.0"}, peer_dependencies: {"engine" => "*"}), {"index.js" => "h"})
      registry.add("left", "1.0.0", It.pkg("left", "1.0.0", dependencies: {"widget" => "1.0.0"}), {"index.js" => "l"})
      registry.add("right", "1.0.0", It.pkg("right", "1.0.0", dependencies: {"helper" => "1.0.0"}), {"index.js" => "r"})

      tmpdir = Path.new(Dir.tempdir, "zap-it-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(tmpdir)
        File.write(tmpdir / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"left":"1.0.0","right":"1.0.0"}}))
        File.write(tmpdir / ".npmrc", "registry=#{registry.base_url}/\n")
        config = Core::Config.new.copy_with(prefix: tmpdir.to_s, store_path: (tmpdir / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)

        inferred = config.infer_context
        state = Commands::Install::State.new(
          config: inferred.config,
          install_config: ic,
          store: ::Store.new(inferred.config.store_path),
          main_package: inferred.main_package,
          lockfile: Data::Lockfile.new(inferred.config.prefix),
          context: inferred,
          npmrc: Data::Npmrc.new(inferred.config.prefix),
          registry_clients: Commands::Install::RegistryClients.new(inferred.config.store_path, Data::Npmrc.new(inferred.config.prefix), pool_max_size: 4),
          pipeline: Concurrency::Pipeline.new(workers: 1),
          reporter: Reporter::Null.new
        )
        state.context.scope_packages(:install).each do |pkg|
          Commands::Install::Resolver.resolve_dependencies_of(pkg, state: state)
        end
        state.pipeline.await

        state.lockfile.mark_transitive_peers
        widget = state.lockfile.get_package("widget", "1.0.0")
        left = state.lockfile.get_package("left", "1.0.0")
        right = state.lockfile.get_package("right", "1.0.0")

        # helper's peer escapes the cycle through both entries: the union
        # semantics mark widget, left and right regardless of traversal order.
        widget.transitive_peer_dependencies.not_nil!["engine"].should_not be_empty
        left.transitive_peer_dependencies.not_nil!["engine"].should_not be_empty
        right.transitive_peer_dependencies.not_nil!["engine"].should_not be_empty
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end

  it "propagates peers across workspace dependency edges" do
    It.with_registry do |registry|
      registry.add("engine", "1.0.0", It.pkg("engine", "1.0.0"), {"index.js" => "1.0.0"})

      tmpdir = Path.new(Dir.tempdir, "zap-it-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(tmpdir / "packages/a")
        Dir.mkdir_p(tmpdir / "packages/b")
        Dir.mkdir_p(tmpdir / "packages/c")
        File.write(tmpdir / "package.json", %({"name":"root","version":"1.0.0","workspaces":["packages/*"],"dependencies":{"@ws/c":"workspace:^"}}))
        File.write(tmpdir / ".npmrc", "registry=#{registry.base_url}/\n")
        File.write(tmpdir / "packages/a/package.json", %({"name":"@ws/a","version":"1.0.0","peerDependencies":{"engine":"*"},"main":"index.js"}))
        File.write(tmpdir / "packages/a/index.js", "a")
        File.write(tmpdir / "packages/b/package.json", %({"name":"@ws/b","version":"1.0.0","dependencies":{"@ws/a":"workspace:^"},"main":"index.js"}))
        File.write(tmpdir / "packages/b/index.js", "b")
        File.write(tmpdir / "packages/c/package.json", %({"name":"@ws/c","version":"1.0.0","dependencies":{"@ws/b":"workspace:^"},"main":"index.js"}))
        File.write(tmpdir / "packages/c/index.js", "c")

        config = Core::Config.new.copy_with(prefix: tmpdir.to_s, store_path: (tmpdir / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)

        inferred = config.infer_context
        state = Commands::Install::State.new(
          config: inferred.config,
          install_config: ic,
          store: ::Store.new(inferred.config.store_path),
          main_package: inferred.main_package,
          lockfile: Data::Lockfile.new(inferred.config.prefix),
          context: inferred,
          npmrc: Data::Npmrc.new(inferred.config.prefix),
          registry_clients: Commands::Install::RegistryClients.new(inferred.config.store_path, Data::Npmrc.new(inferred.config.prefix), pool_max_size: 4),
          pipeline: Concurrency::Pipeline.new(workers: 1),
          reporter: Reporter::Null.new
        )
        state.context.scope_packages(:install).each do |pkg|
          Commands::Install::Resolver.resolve_dependencies_of(pkg, state: state)
        end
        state.pipeline.await

        state.lockfile.mark_transitive_peers
        # @ws/b (a stored transitive workspace) depends on @ws/a through a
        # workspace: pin; @ws/a's peer must reach it via the reverse edge.
        b_key = state.lockfile.packages.keys.find { |k| k.starts_with?("@ws/b@") }
        b_key.should_not be_nil
        b = state.lockfile.packages[b_key.not_nil!]
        b.transitive_peer_dependencies.not_nil!["engine"].should_not be_empty
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end
end

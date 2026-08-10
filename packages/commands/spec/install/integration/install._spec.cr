require "./spec_helper"


describe "install", tags: "integration" do
  it "installs transitive dependencies" do
    It.with_registry do |registry|
      registry.add("b", "1.0.0", It.pkg("b", "1.0.0", dependencies: {"c" => "^1.0.0"}), {"index.js" => "module.exports = 'b';"})
      registry.add("c", "1.2.3", It.pkg("c", "1.2.3"), {"index.js" => "module.exports = 'c';"})
      registry.add("a", "1.0.0", It.pkg("a", "1.0.0", dependencies: {"b" => "^1.0.0"}), {"index.js" => "module.exports = 'a';"})

      It.install_project(registry, %({"name":"app","version":"1.0.0","dependencies":{"a":"^1.0.0"}})) do |project|
        File.exists?(project / "node_modules/a/index.js").should be_true
        File.exists?(project / "node_modules/b/index.js").should be_true
        File.exists?(project / "node_modules/c/index.js").should be_true
      end
    end

  end

  it "resolves caret ranges and dist-tags" do
    It.with_registry do |registry|
      registry.add("range-pkg", "1.5.0", It.pkg("range-pkg", "1.5.0"), {"index.js" => "1.5.0"})
      registry.add("range-pkg", "2.0.0", It.pkg("range-pkg", "2.0.0"), {"index.js" => "2.0.0"})

      It.install_project(registry, %({"name":"app","version":"1.0.0","dependencies":{"range-pkg":"^1.0.0"}})) do |project|
        File.read(project / "node_modules/range-pkg/index.js").should eq("1.5.0")
      end
      It.install_project(registry, %({"name":"app","version":"1.0.0","dependencies":{"range-pkg":"latest"}})) do |project|
        File.read(project / "node_modules/range-pkg/index.js").should eq("2.0.0")
      end
    end

  end

  it "installs dev dependencies and omits them with --production" do
    It.with_registry do |registry|
      registry.add("dep", "1.0.0", It.pkg("dep", "1.0.0"), {"index.js" => "dep"})
      registry.add("devdep", "1.0.0", It.pkg("devdep", "1.0.0"), {"index.js" => "devdep"})

      It.install_project(registry, %({"name":"app","version":"1.0.0","dependencies":{"dep":"1.0.0"},"devDependencies":{"devdep":"1.0.0"}})) do |project|
        File.exists?(project / "node_modules/dep/index.js").should be_true
        File.exists?(project / "node_modules/devdep/index.js").should be_true
      end
      It.install_project(
        registry,
        %({"name":"app","version":"1.0.0","dependencies":{"dep":"1.0.0"},"devDependencies":{"devdep":"1.0.0"}}),
        install_config: Commands::Install::Config.new.copy_with(omit: [Commands::Install::Config::Omit::Dev])
      ) do |project|
        File.exists?(project / "node_modules/dep/index.js").should be_true
        File.exists?(project / "node_modules/devdep/index.js").should be_false
      end
    end

  end

  it "resolves satisfied peer dependencies" do
    It.with_registry do |registry|
      registry.add("peer", "1.2.0", It.pkg("peer", "1.2.0"), {"index.js" => "peer"})
      registry.add("with-peer", "1.0.0", It.pkg("with-peer", "1.0.0", dependencies: {"peer" => "^1.0.0"}, peer_dependencies: {"peer" => "^1.0.0"}), {"index.js" => "wp"})

      It.install_project(registry, %({"name":"app","version":"1.0.0","dependencies":{"with-peer":"1.0.0"}})) do |project|
        File.exists?(project / "node_modules/with-peer/index.js").should be_true
        File.exists?(project / "node_modules/peer/index.js").should be_true
      end
    end

  end

  it "installs without crashing when a peer dependency is missing" do
    It.with_registry do |registry|
      registry.add("peerless", "1.0.0", It.pkg("peerless", "1.0.0", peer_dependencies: {"not-installed" => "^1.0.0"}), {"index.js" => "pl"})

      It.install_project(registry, %({"name":"app","version":"1.0.0","dependencies":{"peerless":"1.0.0"}})) do |project|
        File.exists?(project / "node_modules/peerless/index.js").should be_true
        File.exists?(project / "node_modules/not-installed").should be_false
      end
    end

  end

  it "skips failing optional dependencies" do
    It.with_registry do |registry|
      registry.add("ok", "1.0.0", It.pkg("ok", "1.0.0", optional_dependencies: {"missing-pkg" => "1.0.0"}), {"index.js" => "ok"})

      It.install_project(registry, %({"name":"app","version":"1.0.0","dependencies":{"ok":"1.0.0"}})) do |project|
        File.exists?(project / "node_modules/ok/index.js").should be_true
        File.exists?(project / "node_modules/missing-pkg").should be_false
      end
    end

  end

  it "installs npm aliases under the alias name" do
    It.with_registry do |registry|
      registry.add("real-name", "2.0.0", It.pkg("real-name", "2.0.0"), {"index.js" => "real"})

      It.install_project(registry, %({"name":"app","version":"1.0.0","dependencies":{"my-alias":"npm:real-name@^2.0.0"}})) do |project|
        alias_path = project / "node_modules/my-alias/package.json"
        File.exists?(alias_path).should be_true
        JSON.parse(File.read(alias_path))["name"].should eq("real-name")
      end
    end

  end

  it "installs scoped packages" do
    It.with_registry do |registry|
      registry.add("@scope/pkg", "1.0.0", It.pkg("@scope/pkg", "1.0.0"), {"index.js" => "scoped"})

      It.install_project(registry, %({"name":"app","version":"1.0.0","dependencies":{"@scope/pkg":"^1.0.0"}})) do |project|
        File.exists?(project / "node_modules/@scope/pkg/index.js").should be_true
      end
    end

  end

  it "applies overrides" do
    It.with_registry do |registry|
      registry.add("overridden", "1.0.0", It.pkg("overridden", "1.0.0"), {"index.js" => "1.0.0"})
      registry.add("overridden", "2.0.0", It.pkg("overridden", "2.0.0"), {"index.js" => "2.0.0"})
      registry.add("parent", "1.0.0", It.pkg("parent", "1.0.0", dependencies: {"overridden" => "^1.0.0"}), {"index.js" => "parent"})

      It.install_project(
        registry,
        %({"name":"app","version":"1.0.0","dependencies":{"parent":"1.0.0"},"overrides":{"overridden":"2.0.0"}})
      ) do |project|
        File.read(project / "node_modules/overridden/index.js").should eq("2.0.0")
      end
    end

  end

  it "skips packages with a non-matching os field" do
    It.with_registry do |registry|
      registry.add("posix-only", "1.0.0", It.pkg("posix-only", "1.0.0", os: ["darwin"]), {"index.js" => "mac"})

      It.install_project(registry, %({"name":"app","version":"1.0.0","dependencies":{"posix-only":"1.0.0"}})) do |project|
        File.exists?(project / "node_modules/posix-only").should be_false
      end
    end

  end

  it "links workspace dependencies" do
    It.with_registry do |registry|
      ws_root = Path.new(Dir.tempdir, "zap-ws-test-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(ws_root / "packages/a")
        Dir.mkdir_p(ws_root / "packages/b")
        File.write(ws_root / "package.json", %({"name":"ws-root","version":"1.0.0","workspaces":["packages/*"]}))
        File.write(ws_root / ".npmrc", "registry=#{registry.base_url}/\n")
        File.write(ws_root / "packages/a/package.json", %({"name":"ws-a","version":"1.0.0","main":"index.js"}))
        File.write(ws_root / "packages/a/index.js", "a")
        File.write(ws_root / "packages/b/package.json", %({"name":"ws-b","version":"1.0.0","dependencies":{"ws-a":"1.0.0"}}))
        File.write(ws_root / "packages/b/index.js", "b")

        config = Core::Config.new.copy_with(prefix: ws_root.to_s, store_path: (ws_root / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: false)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)

        # The workspace dependency is linked, not fetched from the registry
        File.exists?(ws_root / "packages/b/node_modules/ws-a/index.js").should be_true
      ensure
        FileUtils.rm_rf(ws_root)
      end
    end

  end

end

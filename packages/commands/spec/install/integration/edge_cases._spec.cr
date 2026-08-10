require "./spec_helper"


describe "install edge cases", tags: "integration" do
  it "tolerates unmet peers with an incompatible installed version" do
    It.with_registry do |registry|
      registry.add("peer", "2.0.0", It.pkg("peer", "2.0.0"), {"index.js" => "peer2"})
      registry.add("needs-peer", "1.0.0", It.pkg("needs-peer", "1.0.0", peer_dependencies: {"peer" => "^1.0.0"}), {"index.js" => "np"})

      It.install_project(
        registry,
        %({"name":"app","version":"1.0.0","dependencies":{"needs-peer":"1.0.0","peer":"2.0.0"}})
      ) do |project|
        File.exists?(project / "node_modules/needs-peer/index.js").should be_true
      end
    end
  end

  it "tolerates missing optional peers" do
    It.with_registry do |registry|
      registry.add("opt-peer", "1.0.0", It.pkg("opt-peer", "1.0.0", peer_dependencies: {"not-installed" => "^1.0.0"},
        extra: {"peerDependenciesMeta" => It.json({"not-installed" => It.json({"optional" => It.json(true)})})}), {"index.js" => "op"})

      It.install_project(registry, %({"name":"app","version":"1.0.0","dependencies":{"opt-peer":"1.0.0"}})) do |project|
        File.exists?(project / "node_modules/opt-peer/index.js").should be_true
        File.exists?(project / "node_modules/not-installed").should be_false
      end
    end
  end

  it "supports multiple versions of the same package" do
    It.with_registry do |registry|
      registry.add("c", "1.0.0", It.pkg("c", "1.0.0"), {"index.js" => "c1"})
      registry.add("c", "2.0.0", It.pkg("c", "2.0.0"), {"index.js" => "c2"})
      registry.add("a1", "1.0.0", It.pkg("a1", "1.0.0", dependencies: {"c" => "1.0.0"}), {"index.js" => "a1"})
      registry.add("a2", "1.0.0", It.pkg("a2", "1.0.0", dependencies: {"c" => "2.0.0"}), {"index.js" => "a2"})

      It.install_project(
        registry,
        %({"name":"app","version":"1.0.0","dependencies":{"a1":"1.0.0","a2":"1.0.0"}})
      ) do |project|
        # One version is hoisted to the root, the other is nested under its dependent
        root = File.read(project / "node_modules/c/index.js")
        nested = Dir.glob(project / "node_modules/a{1,2}/node_modules/c/index.js").map { |p| File.read(p) }
        [root].concat(nested).sort.should eq(["c1", "c2"])
      end
    end
  end

  it "handles circular dependencies" do
    It.with_registry do |registry|
      registry.add("circ-a", "1.0.0", It.pkg("circ-a", "1.0.0", dependencies: {"circ-b" => "1.0.0"}), {"index.js" => "a"})
      registry.add("circ-b", "1.0.0", It.pkg("circ-b", "1.0.0", dependencies: {"circ-a" => "1.0.0"}), {"index.js" => "b"})

      It.install_project(registry, %({"name":"app","version":"1.0.0","dependencies":{"circ-a":"1.0.0"}})) do |project|
        File.exists?(project / "node_modules/circ-a/index.js").should be_true
        File.exists?(project / "node_modules/circ-b/index.js").should be_true
      end
    end
  end

  it "links executable bin scripts" do
    It.with_registry do |registry|
      registry.add("with-bin", "1.0.0", It.pkg("with-bin", "1.0.0", bin: "cli.js"), {"index.js" => "main", "cli.js" => "#!/usr/bin/env node\nprocess.stdout.write('bin-ok')"})

      It.install_project(registry, %({"name":"app","version":"1.0.0","dependencies":{"with-bin":"1.0.0"}})) do |project|
        bin_path = project / "node_modules/.bin/with-bin"
        File.exists?(bin_path).should be_true
        File::Info.executable?(File.realpath(bin_path)).should be_true
        `#{bin_path}`.should eq("bin-ok")
      end
    end
  end

  it "links object-form bin scripts" do
    It.with_registry do |registry|
      registry.add("multi-bin", "1.0.0", It.pkg("multi-bin", "1.0.0", bin: "cli.js",
        extra: {"bin" => It.json({"one" => "one.js", "two" => "two.js"})}), {"index.js" => "main", "one.js" => "one", "two.js" => "two"})

      It.install_project(registry, %({"name":"app","version":"1.0.0","dependencies":{"multi-bin":"1.0.0"}})) do |project|
        File.exists?(project / "node_modules/.bin/one").should be_true
        File.exists?(project / "node_modules/.bin/two").should be_true
      end
    end
  end

  it "supports file: dependencies pointing at a local folder" do
    It.with_registry do |registry|
      tmpdir = Path.new(Dir.tempdir, "zap-it-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(tmpdir / "local-dep")
        File.write(tmpdir / "local-dep/package.json", %({"name":"local-dep","version":"1.0.0","main":"index.js"}))
        File.write(tmpdir / "local-dep/index.js", "local")
        File.write(tmpdir / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"local-dep":"file:local-dep"}}))
        File.write(tmpdir / ".npmrc", "registry=#{registry.base_url}/\n")

        config = Core::Config.new.copy_with(prefix: tmpdir.to_s, store_path: (tmpdir / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: false)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)

        File.read(tmpdir / "node_modules/local-dep/index.js").should eq("local")
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end

  it "supports workspace: protocol dependencies" do
    ws_root = Path.new(Dir.tempdir, "zap-ws-test-#{Random::Secure.hex(4)}")
    begin
      Dir.mkdir_p(ws_root / "packages/a")
      Dir.mkdir_p(ws_root / "packages/b")
      File.write(ws_root / "package.json", %({"name":"ws-root","version":"1.0.0","workspaces":["packages/*"]}))
      File.write(ws_root / "packages/a/package.json", %({"name":"ws-a","version":"1.0.0","main":"index.js"}))
      File.write(ws_root / "packages/a/index.js", "a")
      File.write(ws_root / "packages/b/package.json", %({"name":"ws-b","version":"1.0.0","dependencies":{"ws-a":"workspace:*"}}))
      File.write(ws_root / "packages/b/index.js", "b")

      config = Core::Config.new.copy_with(prefix: ws_root.to_s, store_path: (ws_root / "store").to_s, silent: true)
      ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: false)
      Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)

      File.exists?(ws_root / "packages/b/node_modules/ws-a/index.js").should be_true
    ensure
      FileUtils.rm_rf(ws_root)
    end
  end

  it "preserves bundled dependencies from the tarball" do
    It.with_registry do |registry|
      registry.add("with-bundle", "1.0.0",
        It.pkg("with-bundle", "1.0.0",
          extra: {"bundleDependencies" => It.json(["bundled"])}),
        {"index.js" => "wb", "node_modules/bundled/index.js" => "bundled"})

      It.install_project(registry, %({"name":"app","version":"1.0.0","dependencies":{"with-bundle":"1.0.0"}})) do |project|
        File.exists?(project / "node_modules/with-bundle/index.js").should be_true
        File.exists?(project / "node_modules/with-bundle/node_modules/bundled/index.js").should be_true
      end
    end
  end

  it "writes a lockfile and reinstalls from it frozen" do
    It.with_registry do |registry|
      registry.add("locked", "1.0.0", It.pkg("locked", "1.0.0"), {"index.js" => "locked"})

      tmpdir = Path.new(Dir.tempdir, "zap-it-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(tmpdir)
        File.write(tmpdir / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"locked":"1.0.0"}}))
        File.write(tmpdir / ".npmrc", "registry=#{registry.base_url}/\n")
        config = Core::Config.new.copy_with(prefix: tmpdir.to_s, store_path: (tmpdir / "store").to_s, silent: true)

        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)
        File.exists?(tmpdir / "zap.lock").should be_true

        FileUtils.rm_rf(tmpdir / "node_modules")
        frozen = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: true, save: true)
        Commands::Install.run(config, frozen, raise_on_failure: true, reporter: Reporter::Null.new)
        File.exists?(tmpdir / "node_modules/locked/index.js").should be_true
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end
end

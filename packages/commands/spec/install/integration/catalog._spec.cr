require "./spec_helper"

# The catalog: protocol (pnpm / yarn berry parity): a dependency specifier
# resolves to the version range defined once at the workspace root.
describe "catalogs", tags: "integration" do
  it "resolves the default catalog reference to its range" do
    It.with_registry do |registry|
      registry.add("react", "17.0.2", It.pkg("react", "17.0.2"), {"index.js" => "17.0.2"})
      registry.add("react", "18.3.1", It.pkg("react", "18.3.1"), {"index.js" => "18.3.1"})

      It.install_project(registry, %({"name":"app","version":"1.0.0","dependencies":{"react":"catalog:"},"zap":{"catalog":{"react":"^18.3.1"}}})) do |project|
        # catalog: is the shorthand for catalog:default
        File.read(project / "node_modules/react/index.js").should eq("18.3.1")
      end
    end
  end

  it "resolves a named catalog reference" do
    It.with_registry do |registry|
      registry.add("react", "17.0.2", It.pkg("react", "17.0.2"), {"index.js" => "17.0.2"})
      registry.add("react", "18.3.1", It.pkg("react", "18.3.1"), {"index.js" => "18.3.1"})

      It.install_project(registry, %({"name":"app","version":"1.0.0","dependencies":{"react":"catalog:react17"},"zap":{"catalogs":{"react17":{"react":"^17.0.2"}}}})) do |project|
        File.read(project / "node_modules/react/index.js").should eq("17.0.2")
      end
    end
  end

  it "lets workspace members use different catalogs for the same name" do
    It.with_registry do |registry|
      registry.add("react", "17.0.2", It.pkg("react", "17.0.2"), {"index.js" => "17.0.2"})
      registry.add("react", "18.3.1", It.pkg("react", "18.3.1"), {"index.js" => "18.3.1"})

      ws_root = Path.new(Dir.tempdir, "zap-ws-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(ws_root / "packages/a")
        Dir.mkdir_p(ws_root / "packages/b")
        File.write(ws_root / "package.json", %({"name":"ws","version":"1.0.0","workspaces":["packages/*"],"zap":{"catalog":{"react":"^18.3.1"},"catalogs":{"react17":{"react":"^17.0.2"}}}}))
        File.write(ws_root / ".npmrc", "registry=#{registry.base_url}/\n")
        File.write(ws_root / "packages/a/package.json", %({"name":"a","version":"1.0.0","dependencies":{"react":"catalog:"}}))
        File.write(ws_root / "packages/b/package.json", %({"name":"b","version":"1.0.0","dependencies":{"react":"catalog:react17"}}))
        config = Core::Config.new.copy_with(prefix: ws_root.to_s, store_path: (ws_root / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)

        # Both versions are resolved, and each member is pinned to its own
        # catalog's version regardless of which one the hoisting placed at
        # the root.
        lock = File.read(ws_root / "zap.lock")
        lock.should contain("react@18.3.1")
        lock.should contain("react@17.0.2")
        lockfile = Data::Lockfile.new(ws_root)
        lockfile.roots["a"].dependency_specifier?("react").to_s.should eq("18.3.1")
        lockfile.roots["b"].dependency_specifier?("react").to_s.should eq("17.0.2")
      ensure
        FileUtils.rm_rf(ws_root)
      end
    end
  end

  it "fails when the default catalog has no entry for the name" do
    It.with_registry do |registry|
      registry.add("react", "18.3.1", It.pkg("react", "18.3.1"), {"index.js" => "18.3.1"})

      raised = false
      begin
        It.install_project(registry, %({"name":"app","version":"1.0.0","dependencies":{"react":"catalog:"},"zap":{"catalog":{"lodash":"^4.0.0"}}})) { |_| }
      rescue ex
        raised = true
        ex.message.not_nil!.should contain("no entry for react")
      end
      raised.should be_true
    end
  end

  it "fails when the referenced catalog is not defined" do
    It.with_registry do |registry|
      registry.add("react", "18.3.1", It.pkg("react", "18.3.1"), {"index.js" => "18.3.1"})

      raised = false
      begin
        It.install_project(registry, %({"name":"app","version":"1.0.0","dependencies":{"react":"catalog:missing"},"zap":{"catalog":{"react":"^18.3.1"}}})) { |_| }
      rescue ex
        raised = true
        ex.message.not_nil!.should contain("catalog")
      end
      raised.should be_true
    end
  end

  it "fails when no catalog is defined" do
    It.with_registry do |registry|
      registry.add("react", "18.3.1", It.pkg("react", "18.3.1"), {"index.js" => "18.3.1"})

      raised = false
      begin
        It.install_project(registry, %({"name":"app","version":"1.0.0","dependencies":{"react":"catalog:"}})) { |_| }
      rescue ex
        raised = true
        ex.message.not_nil!.should contain("catalog")
      end
      raised.should be_true
    end
  end

  it "supports the catalog reference in devDependencies" do
    It.with_registry do |registry|
      registry.add("dev-tool", "1.0.0", It.pkg("dev-tool", "1.0.0"), {"index.js" => "d"})

      It.install_project(registry, %({"name":"app","version":"1.0.0","devDependencies":{"dev-tool":"catalog:"},"zap":{"catalog":{"dev-tool":"^1.0.0"}}})) do |project|
        File.read(project / "node_modules/dev-tool/index.js").should eq("d")
      end
    end
  end

  it "pins the resolved version and honors it on reinstall" do
    It.with_registry do |registry|
      registry.add("react", "18.3.1", It.pkg("react", "18.3.1"), {"index.js" => "18.3.1"})

      tmpdir = Path.new(Dir.tempdir, "zap-it-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(tmpdir)
        File.write(tmpdir / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"react":"catalog:"},"zap":{"catalog":{"react":"^18.3.1"}}}))
        File.write(tmpdir / ".npmrc", "registry=#{registry.base_url}/\n")
        config = Core::Config.new.copy_with(prefix: tmpdir.to_s, store_path: (tmpdir / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)
        File.read(tmpdir / "zap.lock").should contain("react@18.3.1")

        # A plain reinstall keeps the pinned version
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)
        File.read(tmpdir / "node_modules/react/index.js").should eq("18.3.1")
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end

  it "expands the catalog reference in peerDependencies" do
    It.with_registry do |registry|
      registry.add("react", "16.0.0", It.pkg("react", "16.0.0"), {"index.js" => "16.0.0"})

      ws_root = Path.new(Dir.tempdir, "zap-ws-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(ws_root / "packages/a")
        Dir.mkdir_p(ws_root / "packages/b")
        File.write(ws_root / "package.json", %({"name":"ws","version":"1.0.0","workspaces":["packages/*"],"dependencies":{"react":"16.0.0"},"zap":{"catalog":{"react":"^18.3.1"}}}))
        File.write(ws_root / ".npmrc", "registry=#{registry.base_url}/\n")
        File.write(ws_root / "packages/a/package.json", %({"name":"a","version":"1.0.0","peerDependencies":{"react":"catalog:"}}))
        File.write(ws_root / "packages/b/package.json", %({"name":"b","version":"1.0.0","dependencies":{"a":"workspace:^1.0.0"}}))
        config = Core::Config.new.copy_with(prefix: ws_root.to_s, store_path: (ws_root / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true, check_peer_dependencies: true)
        out_io = IO::Memory.new
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Plain.new(out_io))

        # The catalog peer range (^18.3.1) is not satisfied by the root's
        # react 16.0.0, so the peer is reported as unmet.
        out_io.to_s.should contain("peer")
        out_io.to_s.should contain("react")
      ensure
        FileUtils.rm_rf(ws_root)
      end
    end
  end

  it "resolves an alias stored in a catalog entry" do
    It.with_registry do |registry|
      registry.add("real", "1.0.0", It.pkg("real", "1.0.0"), {"index.js" => "real"})

      It.install_project(registry, %({"name":"app","version":"1.0.0","dependencies":{"my-alias":"catalog:"},"zap":{"catalog":{"my-alias":"npm:real@^1.0.0"}}})) do |project|
        File.read(project / "node_modules/my-alias/index.js").should eq("real")
      end
    end
  end

  it "resolves a catalog reference in overrides" do
    It.with_registry do |registry|
      registry.add("dep", "1.0.0", It.pkg("dep", "1.0.0"), {"index.js" => "1.0.0"})
      registry.add("dep", "2.0.0", It.pkg("dep", "2.0.0"), {"index.js" => "2.0.0"})
      registry.add("parent", "1.0.0", It.pkg("parent", "1.0.0", dependencies: {"dep" => "^1.0.0"}), {"index.js" => "p"})

      It.install_project(registry, %({"name":"app","version":"1.0.0","dependencies":{"parent":"1.0.0"},"overrides":{"dep":"catalog:"},"zap":{"catalog":{"dep":"^2.0.0"}}})) do |project|
        File.read(project / "node_modules/dep/index.js").should eq("2.0.0")
      end
    end
  end

  it "rewrites the specifier literally when updating a catalog dependency" do
    It.with_registry do |registry|
      registry.add("react", "18.3.1", It.pkg("react", "18.3.1"), {"index.js" => "18.3.1"})
      registry.add("react", "19.0.0", It.pkg("react", "19.0.0"), {"index.js" => "19.0.0"})

      tmpdir = Path.new(Dir.tempdir, "zap-it-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(tmpdir)
        File.write(tmpdir / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"react":"catalog:"},"zap":{"catalog":{"react":"^18.3.1"}}}))
        File.write(tmpdir / ".npmrc", "registry=#{registry.base_url}/\n")
        config = Core::Config.new.copy_with(prefix: tmpdir.to_s, store_path: (tmpdir / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)

        # An explicit range update leaves the catalog and writes the literal
        # specifier (documented divergence: the catalog entry itself is not
        # edited).
        targeted = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true, updated_packages: ["react@^19.0.0"])
        Commands::Install.run(config, targeted, raise_on_failure: true, reporter: Reporter::Null.new)
        pkg = JSON.parse(File.read(tmpdir / "package.json"))
        pkg["dependencies"]["react"].as_s.should eq("^19.0.0")
        File.read(tmpdir / "node_modules/react/index.js").should eq("19.0.0")
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end

  it "fails a frozen install when the catalog entry changed" do
    It.with_registry do |registry|
      registry.add("react", "18.3.1", It.pkg("react", "18.3.1"), {"index.js" => "18.3.1"})
      registry.add("react", "19.0.0", It.pkg("react", "19.0.0"), {"index.js" => "19.0.0"})

      tmpdir = Path.new(Dir.tempdir, "zap-it-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(tmpdir)
        File.write(tmpdir / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"react":"catalog:"},"zap":{"catalog":{"react":"^18.3.1"}}}))
        File.write(tmpdir / ".npmrc", "registry=#{registry.base_url}/\n")
        config = Core::Config.new.copy_with(prefix: tmpdir.to_s, store_path: (tmpdir / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)

        # The catalog entry moves the dependency out of the pinned resolution
        File.write(tmpdir / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"react":"catalog:"},"zap":{"catalog":{"react":"^19.0.0"}}}))
        expect_raises(Exception, /frozen-lockfile/) do
          Commands::Install.run(config, ic.copy_with(frozen_lockfile: true), raise_on_failure: true, reporter: Reporter::Null.new)
        end
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end
end

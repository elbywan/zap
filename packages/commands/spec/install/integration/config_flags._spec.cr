require "./spec_helper"

# Configuration flags: os/cpu negation patterns, the msgpack lockfile
# format, --no-workspaces, and multi-worker resolution.
describe "configuration flags", tags: "integration" do
  it "installs a package whose os field excludes other platforms" do
    It.with_registry do |registry|
      registry.add("not-windows", "1.0.0", It.pkg("not-windows", "1.0.0", os: ["!win32"]), {"index.js" => "ok"})

      It.install_project(registry, %({"name":"app","version":"1.0.0","dependencies":{"not-windows":"1.0.0"}})) do |project|
        File.read(project / "node_modules/not-windows/index.js").should eq("ok")
      end
    end
  end

  it "skips a package whose os field excludes this platform" do
    It.with_registry do |registry|
      registry.add("no-linux", "1.0.0", It.pkg("no-linux", "1.0.0", os: ["!linux"]), {"index.js" => "nope"})

      It.install_project(registry, %({"name":"app","version":"1.0.0","dependencies":{"no-linux":"1.0.0"}})) do |project|
        File.exists?(project / "node_modules/no-linux").should be_false
      end
    end
  end

  it "writes and reads a msgpack lockfile" do
    It.with_registry do |registry|
      registry.add("mp", "1.0.0", It.pkg("mp", "1.0.0"), {"index.js" => "m"})

      tmpdir = Path.new(Dir.tempdir, "zap-it-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(tmpdir)
        File.write(tmpdir / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"mp":"1.0.0"}}))
        File.write(tmpdir / ".npmrc", "registry=#{registry.base_url}/\n")
        config = Core::Config.new.copy_with(prefix: tmpdir.to_s, store_path: (tmpdir / "store").to_s, silent: true, lockfile_format: Data::Lockfile::Format::MessagePack)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)

        lockfile_path = tmpdir / "zap.lock"
        File.exists?(lockfile_path).should be_true
        # Not the YAML document marker
        File.read(lockfile_path).starts_with?("---").should be_false

        # A frozen reinstall loads the msgpack lockfile without re-resolving
        FileUtils.rm_rf(tmpdir / "node_modules")
        frozen = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: true, save: false)
        Commands::Install.run(config, frozen, raise_on_failure: true, reporter: Reporter::Null.new)
        File.read(tmpdir / "node_modules/mp/index.js").should eq("m")
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end

  it "treats a nested package as standalone with --no-workspaces" do
    It.with_registry do |registry|
      registry.add("only-a", "1.0.0", It.pkg("only-a", "1.0.0"), {"index.js" => "a"})

      ws_root = Path.new(Dir.tempdir, "zap-ws-test-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(ws_root / "packages/a")
        File.write(ws_root / "package.json", %({"name":"ws-root","version":"1.0.0","workspaces":["packages/*"]}))
        File.write(ws_root / ".npmrc", "registry=#{registry.base_url}/\n")
        File.write(ws_root / "packages/a/package.json", %({"name":"ws-a","version":"1.0.0","dependencies":{"only-a":"1.0.0"}}))
        File.write(ws_root / "packages/a/index.js", "ws-a")
        File.write(ws_root / "packages/a/.npmrc", "registry=#{registry.base_url}/\n")

        config = Core::Config.new.copy_with(prefix: (ws_root / "packages/a").to_s, store_path: (ws_root / "store").to_s, silent: true, no_workspaces: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: false)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)

        # Installed into the package's own node_modules, nothing hoisted to the root
        File.read(ws_root / "packages/a/node_modules/only-a/index.js").should eq("a")
        File.exists?(ws_root / "node_modules").should be_false
      ensure
        FileUtils.rm_rf(ws_root)
      end
    end
  end

  it "installs with multiple workers" do
    It.with_registry do |registry|
      registry.add("b", "1.0.0", It.pkg("b", "1.0.0"), {"index.js" => "b"})
      registry.add("a", "1.0.0", It.pkg("a", "1.0.0", dependencies: {"b" => "1.0.0"}), {"index.js" => "a"})

      ic = Commands::Install::Config.new.copy_with(workers: 4)
      It.install_project(registry, %({"name":"app","version":"1.0.0","dependencies":{"a":"1.0.0"}}), install_config: ic) do |project|
        File.read(project / "node_modules/a/index.js").should eq("a")
        File.read(project / "node_modules/b/index.js").should eq("b")
      end
    end
  end
end

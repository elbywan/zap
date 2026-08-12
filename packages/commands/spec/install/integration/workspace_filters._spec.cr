require "./spec_helper"

# Workspace command scoping: --filter limits the install to the selected
# workspace(s), mirroring yarn workspaces focus / pnpm --filter.
describe "workspace filters", tags: "integration" do
  it "installs only the dependencies of the filtered workspace" do
    It.with_registry do |registry|
      registry.add("only-a", "1.0.0", It.pkg("only-a", "1.0.0"), {"index.js" => "a"})
      registry.add("only-b", "1.0.0", It.pkg("only-b", "1.0.0"), {"index.js" => "b"})

      ws_root = Path.new(Dir.tempdir, "zap-ws-test-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(ws_root / "packages/a")
        Dir.mkdir_p(ws_root / "packages/b")
        File.write(ws_root / "package.json", %({"name":"ws-root","version":"1.0.0","workspaces":["packages/*"]}))
        File.write(ws_root / ".npmrc", "registry=#{registry.base_url}/\n")
        File.write(ws_root / "packages/a/package.json", %({"name":"ws-a","version":"1.0.0","dependencies":{"only-a":"1.0.0"}}))
        File.write(ws_root / "packages/a/index.js", "ws-a")
        File.write(ws_root / "packages/b/package.json", %({"name":"ws-b","version":"1.0.0","dependencies":{"only-b":"1.0.0"}}))
        File.write(ws_root / "packages/b/index.js", "ws-b")

        config = Core::Config.new.copy_with(prefix: ws_root.to_s, store_path: (ws_root / "store").to_s, silent: true, filters: [Workspaces::Filter.new("ws-a")])
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: false)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)

        # ws-a's dependency is installed, ws-b's is not
        File.exists?(ws_root / "node_modules/only-a").should be_true
        File.exists?(ws_root / "node_modules/only-b").should be_false
      ensure
        FileUtils.rm_rf(ws_root)
      end
    end
  end

  it "installs no workspace dependencies without a filter" do
    It.with_registry do |registry|
      registry.add("only-a", "1.0.0", It.pkg("only-a", "1.0.0"), {"index.js" => "a"})
      registry.add("only-b", "1.0.0", It.pkg("only-b", "1.0.0"), {"index.js" => "b"})

      ws_root = Path.new(Dir.tempdir, "zap-ws-test-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(ws_root / "packages/a")
        Dir.mkdir_p(ws_root / "packages/b")
        File.write(ws_root / "package.json", %({"name":"ws-root","version":"1.0.0","workspaces":["packages/*"]}))
        File.write(ws_root / ".npmrc", "registry=#{registry.base_url}/\n")
        File.write(ws_root / "packages/a/package.json", %({"name":"ws-a","version":"1.0.0","dependencies":{"only-a":"1.0.0"}}))
        File.write(ws_root / "packages/a/index.js", "ws-a")
        File.write(ws_root / "packages/b/package.json", %({"name":"ws-b","version":"1.0.0","dependencies":{"only-b":"1.0.0"}}))
        File.write(ws_root / "packages/b/index.js", "ws-b")

        config = Core::Config.new.copy_with(prefix: ws_root.to_s, store_path: (ws_root / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: false)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)

        # Both workspaces' dependencies are installed
        File.exists?(ws_root / "node_modules/only-a").should be_true
        File.exists?(ws_root / "node_modules/only-b").should be_true
      ensure
        FileUtils.rm_rf(ws_root)
      end
    end
  end

  it "includes dependents with a ... filter prefix" do
    It.with_registry do |registry|
      registry.add("only-a", "1.0.0", It.pkg("only-a", "1.0.0"), {"index.js" => "a"})
      registry.add("only-b", "1.0.0", It.pkg("only-b", "1.0.0"), {"index.js" => "b"})

      ws_root = Path.new(Dir.tempdir, "zap-ws-test-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(ws_root / "packages/a")
        Dir.mkdir_p(ws_root / "packages/b")
        File.write(ws_root / "package.json", %({"name":"ws-root","version":"1.0.0","workspaces":["packages/*"]}))
        File.write(ws_root / ".npmrc", "registry=#{registry.base_url}/\n")
        File.write(ws_root / "packages/a/package.json", %({"name":"ws-a","version":"1.0.0","dependencies":{"only-a":"1.0.0"}}))
        File.write(ws_root / "packages/a/index.js", "ws-a")
        File.write(ws_root / "packages/b/package.json", %({"name":"ws-b","version":"1.0.0","dependencies":{"only-b":"1.0.0","ws-a":"1.0.0"}}))
        File.write(ws_root / "packages/b/index.js", "ws-b")

        config = Core::Config.new.copy_with(prefix: ws_root.to_s, store_path: (ws_root / "store").to_s, silent: true, filters: [Workspaces::Filter.new("...ws-a")])
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: false)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)

        # ws-b depends on ws-a, so it is included through the dependents prefix
        File.exists?(ws_root / "node_modules/only-a").should be_true
        File.exists?(ws_root / "node_modules/only-b").should be_true
      ensure
        FileUtils.rm_rf(ws_root)
      end
    end
  end

  it "installs workspace dependencies with the isolated strategy" do
    It.with_registry do |registry|
      registry.add("only-a", "1.0.0", It.pkg("only-a", "1.0.0"), {"index.js" => "a"})

      ws_root = Path.new(Dir.tempdir, "zap-ws-test-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(ws_root / "packages/a")
        File.write(ws_root / "package.json", %({"name":"ws-root","version":"1.0.0","workspaces":["packages/*"]}))
        File.write(ws_root / ".npmrc", "registry=#{registry.base_url}/\n")
        File.write(ws_root / "packages/a/package.json", %({"name":"ws-a","version":"1.0.0","dependencies":{"only-a":"1.0.0"}}))
        File.write(ws_root / "packages/a/index.js", "ws-a")

        config = Core::Config.new.copy_with(prefix: ws_root.to_s, store_path: (ws_root / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: false, strategy: Data::Package::InstallStrategy::Isolated)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)

        File.symlink?(ws_root / "packages/a/node_modules/only-a").should be_true
        Dir.exists?(ws_root / "node_modules/.store").should be_true
      ensure
        FileUtils.rm_rf(ws_root)
      end
    end
  end

  it "installs workspace dependencies with the pnp strategy" do
    It.with_registry do |registry|
      registry.add("only-a", "1.0.0", It.pkg("only-a", "1.0.0"), {"index.js" => "a"})

      ws_root = Path.new(Dir.tempdir, "zap-ws-test-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(ws_root / "packages/a")
        File.write(ws_root / "package.json", %({"name":"ws-root","version":"1.0.0","workspaces":["packages/*"]}))
        File.write(ws_root / ".npmrc", "registry=#{registry.base_url}/\n")
        File.write(ws_root / "packages/a/package.json", %({"name":"ws-a","version":"1.0.0","dependencies":{"only-a":"1.0.0"}}))
        File.write(ws_root / "packages/a/index.js", "ws-a")

        config = Core::Config.new.copy_with(prefix: ws_root.to_s, store_path: (ws_root / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: false, strategy: Data::Package::InstallStrategy::Pnp)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)

        File.exists?(ws_root / ".pnp.cjs").should be_true
        Dir.children(ws_root / "node_modules").sort.should eq([".pnp", ".zap-state"])
      ensure
        FileUtils.rm_rf(ws_root)
      end
    end
  end
end

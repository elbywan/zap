require "./spec_helper"


# Workspace behaviors, mirroring yarn's workspace tests: cross-dependencies,
# workspace-vs-registry precedence, transitive workspace deps, nohoist.
describe "workspaces", tags: "integration" do
  it "links cross-workspace dependencies via a version range" do
    It.with_registry do |registry|
      ws_root = Path.new(Dir.tempdir, "zap-ws-test-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(ws_root / "packages/a")
        Dir.mkdir_p(ws_root / "packages/b")
        File.write(ws_root / "package.json", %({"name":"ws-root","version":"1.0.0","workspaces":["packages/*"]}))
        File.write(ws_root / "packages/a/package.json", %({"name":"ws-a","version":"1.0.0","main":"index.js"}))
        File.write(ws_root / "packages/a/index.js", "ws-a")
        File.write(ws_root / "packages/b/package.json", %({"name":"ws-b","version":"1.0.0","dependencies":{"ws-a":"1.0.0"}}))
        File.write(ws_root / "packages/b/index.js", "ws-b")

        config = Core::Config.new.copy_with(prefix: ws_root.to_s, store_path: (ws_root / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: false)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)

        File.read(ws_root / "packages/b/node_modules/ws-a/index.js").should eq("ws-a")
      ensure
        FileUtils.rm_rf(ws_root)
      end
    end
  end

  it "prefers the workspace over a same-named registry package" do
    It.with_registry do |registry|
      registry.add("ws-a", "1.0.0", It.pkg("ws-a", "1.0.0"), {"index.js" => "registry"})

      ws_root = Path.new(Dir.tempdir, "zap-ws-test-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(ws_root / "packages/a")
        Dir.mkdir_p(ws_root / "packages/b")
        File.write(ws_root / "package.json", %({"name":"ws-root","version":"1.0.0","workspaces":["packages/*"]}))
        File.write(ws_root / ".npmrc", "registry=#{registry.base_url}/\n")
        File.write(ws_root / "packages/a/package.json", %({"name":"ws-a","version":"1.0.0","main":"index.js"}))
        File.write(ws_root / "packages/a/index.js", "workspace")
        File.write(ws_root / "packages/b/package.json", %({"name":"ws-b","version":"1.0.0","dependencies":{"ws-a":"1.0.0"}}))
        File.write(ws_root / "packages/b/index.js", "ws-b")

        config = Core::Config.new.copy_with(prefix: ws_root.to_s, store_path: (ws_root / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: false)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)

        File.read(ws_root / "packages/b/node_modules/ws-a/index.js").should eq("workspace")
      ensure
        FileUtils.rm_rf(ws_root)
      end
    end
  end

  it "links transitive workspace dependencies" do
    It.with_registry do |registry|
      ws_root = Path.new(Dir.tempdir, "zap-ws-test-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(ws_root / "packages/a")
        Dir.mkdir_p(ws_root / "packages/b")
        Dir.mkdir_p(ws_root / "packages/c")
        File.write(ws_root / "package.json", %({"name":"ws-root","version":"1.0.0","workspaces":["packages/*"]}))
        File.write(ws_root / "packages/a/package.json", %({"name":"ws-a","version":"1.0.0","main":"index.js"}))
        File.write(ws_root / "packages/a/index.js", "ws-a")
        File.write(ws_root / "packages/b/package.json", %({"name":"ws-b","version":"1.0.0","dependencies":{"ws-a":"1.0.0"}}))
        File.write(ws_root / "packages/b/index.js", "ws-b")
        File.write(ws_root / "packages/c/package.json", %({"name":"ws-c","version":"1.0.0","dependencies":{"ws-b":"1.0.0"}}))
        File.write(ws_root / "packages/c/index.js", "ws-c")

        config = Core::Config.new.copy_with(prefix: ws_root.to_s, store_path: (ws_root / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: false)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)

        File.exists?(ws_root / "packages/c/node_modules/ws-b/index.js").should be_true
        File.exists?(ws_root / "packages/b/node_modules/ws-a/index.js").should be_true
      ensure
        FileUtils.rm_rf(ws_root)
      end
    end
  end

  it "installs registry dependencies for workspaces" do
    It.with_registry do |registry|
      registry.add("reg-dep", "1.0.0", It.pkg("reg-dep", "1.0.0"), {"index.js" => "reg"})

      ws_root = Path.new(Dir.tempdir, "zap-ws-test-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(ws_root / "packages/a")
        File.write(ws_root / "package.json", %({"name":"ws-root","version":"1.0.0","workspaces":["packages/*"]}))
        File.write(ws_root / ".npmrc", "registry=#{registry.base_url}/\n")
        File.write(ws_root / "packages/a/package.json", %({"name":"ws-a","version":"1.0.0","dependencies":{"reg-dep":"1.0.0"}}))
        File.write(ws_root / "packages/a/index.js", "ws-a")

        config = Core::Config.new.copy_with(prefix: ws_root.to_s, store_path: (ws_root / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: false)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)

        # Classic strategy hoists the registry dependency to the root node_modules
        File.read(ws_root / "node_modules/reg-dep/index.js").should eq("reg")
      ensure
        FileUtils.rm_rf(ws_root)
      end
    end
  end
  it "honors the nohoist pattern for workspace dependencies" do
    It.with_registry do |registry|
      registry.add("only-a", "1.0.0", It.pkg("only-a", "1.0.0"), {"index.js" => "a"})

      ws_root = Path.new(Dir.tempdir, "zap-ws-test-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(ws_root / "packages/a")
        File.write(ws_root / "package.json", %({"name":"ws-root","version":"1.0.0","workspaces":{"packages":["packages/*"],"nohoist":["**/only-a"]}}))
        File.write(ws_root / ".npmrc", "registry=#{registry.base_url}/\n")
        File.write(ws_root / "packages/a/package.json", %({"name":"ws-a","version":"1.0.0","dependencies":{"only-a":"1.0.0"}}))
        File.write(ws_root / "packages/a/index.js", "ws-a")

        config = Core::Config.new.copy_with(prefix: ws_root.to_s, store_path: (ws_root / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: false)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)

        # The nohoisted dependency stays in the workspace's node_modules
        File.read(ws_root / "packages/a/node_modules/only-a/index.js").should eq("a")
        File.exists?(ws_root / "node_modules/only-a").should be_false
      ensure
        FileUtils.rm_rf(ws_root)
      end
    end
  end
  it "does not expose undeclared workspaces at the root (pnpm model)" do
    It.with_registry do |registry|
      ws_root = Path.new(Dir.tempdir, "zap-ws-test-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(ws_root / "packages/a")
        File.write(ws_root / "package.json", %({"name":"ws-root","version":"1.0.0","workspaces":["packages/*"]}))
        File.write(ws_root / ".npmrc", "registry=#{registry.base_url}/\n")
        File.write(ws_root / "packages/a/package.json", %({"name":"ws-a","version":"1.0.0","main":"index.js"}))
        File.write(ws_root / "packages/a/index.js", "module.exports = {name: 'ws-a'}")

        config = Core::Config.new.copy_with(prefix: ws_root.to_s, store_path: (ws_root / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: false)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)

        # Unlike npm/yarn, undeclared workspaces are not require-able from the root
        File.exists?(ws_root / "node_modules/ws-a").should be_false
        out_io = IO::Memory.new
        err_io = IO::Memory.new
        status = Process.run("node", ["-e", "require('ws-a')"], chdir: ws_root.to_s, output: out_io, error: err_io)
        status.success?.should be_false
      ensure
        FileUtils.rm_rf(ws_root)
      end
    end
  end

  it "links a workspace declared as a root dependency" do
    It.with_registry do |registry|
      ws_root = Path.new(Dir.tempdir, "zap-ws-test-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(ws_root / "packages/a")
        File.write(ws_root / "package.json", %({"name":"ws-root","version":"1.0.0","workspaces":["packages/*"],"dependencies":{"ws-a":"1.0.0"}}))
        File.write(ws_root / ".npmrc", "registry=#{registry.base_url}/\n")
        File.write(ws_root / "packages/a/package.json", %({"name":"ws-a","version":"1.0.0","main":"index.js"}))
        File.write(ws_root / "packages/a/index.js", "module.exports = {name: 'ws-a'}")

        config = Core::Config.new.copy_with(prefix: ws_root.to_s, store_path: (ws_root / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: false)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)

        File.read(ws_root / "node_modules/ws-a/index.js").should contain("ws-a")
        out_io = IO::Memory.new
        status = Process.run("node", ["-e", "process.stdout.write(JSON.stringify(require('ws-a')))"], chdir: ws_root.to_s, output: out_io)
        status.success?.should be_true
        out_io.to_s.should eq(%({"name":"ws-a"}))
      ensure
        FileUtils.rm_rf(ws_root)
      end
    end
  end
end

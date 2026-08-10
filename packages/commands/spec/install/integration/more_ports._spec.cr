require "./spec_helper"

# More ports from yarn/npm/pnpm: --ignore-optional, install scripts reading
# stdin, installs launched from workspace subdirectories, pnp instance
# deduplication and hoisting invariants for conflicting topologies.
describe "more ports", tags: "integration" do
  it "omits optional dependencies with the omit-optional flag" do
    It.with_registry do |registry|
      registry.add("opt-dep", "1.0.0", It.pkg("opt-dep", "1.0.0"), {"index.js" => "o"})
      registry.add("reg-dep", "1.0.0", It.pkg("reg-dep", "1.0.0"), {"index.js" => "r"})

      ic = Commands::Install::Config.new.copy_with(omit: [Commands::Install::Config::Omit::Optional])
      It.install_project(registry, %({"name":"app","version":"1.0.0","dependencies":{"reg-dep":"1.0.0"},"optionalDependencies":{"opt-dep":"1.0.0"}}), install_config: ic) do |project|
        File.read(project / "node_modules/reg-dep/index.js").should eq("r")
        File.exists?(project / "node_modules/opt-dep").should be_false
      end
    end
  end

  it "does not hang when an install script reads from stdin" do
    It.with_registry do |registry|
      registry.add("stdin-script", "1.0.0", It.pkg("stdin-script", "1.0.0",
        scripts: {"postinstall" => "node -e \"require('fs').readFileSync(0); require('fs').writeFileSync('read-stdin.txt', 'ok')\""}),
        {"index.js" => "s"})

      It.install_project(registry, %({"name":"app","version":"1.0.0","dependencies":{"stdin-script":"1.0.0"}})) do |project|
        # The install completed: stdin is closed for install scripts
        File.read(project / "node_modules/stdin-script/read-stdin.txt").should eq("ok")
      end
    end
  end

  it "runs the install from the workspace root when launched from a subdirectory" do
    It.with_registry do |registry|
      registry.add("only-a", "1.0.0", It.pkg("only-a", "1.0.0"), {"index.js" => "a"})

      ws_root = Path.new(Dir.tempdir, "zap-ws-test-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(ws_root / "packages/a")
        File.write(ws_root / "package.json", %({"name":"ws-root","version":"1.0.0","workspaces":["packages/*"]}))
        File.write(ws_root / ".npmrc", "registry=#{registry.base_url}/\n")
        File.write(ws_root / "packages/a/package.json", %({"name":"ws-a","version":"1.0.0","dependencies":{"only-a":"1.0.0"}}))
        File.write(ws_root / "packages/a/index.js", "ws-a")

        config = Core::Config.new.copy_with(prefix: (ws_root / "packages/a").to_s, store_path: (ws_root / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: false)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)

        # The prefix is rewritten to the workspace root, which hoists the dep
        File.read(ws_root / "node_modules/only-a/index.js").should eq("a")
      ensure
        FileUtils.rm_rf(ws_root)
      end
    end
  end

  it "deduplicates a shared package into a single pnp instance" do
    It.with_registry do |registry|
      registry.add("shared-pkg", "1.0.0", It.pkg("shared-pkg", "1.0.0"), {"index.js" => "module.exports = {}"})
      registry.add("user-x", "1.0.0", It.pkg("user-x", "1.0.0", dependencies: {"shared-pkg" => "1.0.0"}), {"index.js" => "module.exports = require('shared-pkg')"})
      registry.add("user-y", "1.0.0", It.pkg("user-y", "1.0.0", dependencies: {"shared-pkg" => "1.0.0"}), {"index.js" => "module.exports = require('shared-pkg')"})

      ic = Commands::Install::Config.new.copy_with(strategy: Data::Package::InstallStrategy::Pnp)
      It.install_project(registry, %({"name":"app","version":"1.0.0","dependencies":{"user-x":"1.0.0","user-y":"1.0.0"}}), install_config: ic) do |project|
        out_io = IO::Memory.new
        err_io = IO::Memory.new
        status = Process.run("node", ["-e", "process.stdout.write(JSON.stringify(require('user-x') === require('user-y')))"],
          chdir: project.to_s, output: out_io, error: err_io, env: {"NODE_OPTIONS" => "--require #{project}/.pnp.cjs"})
        status.success?.should be_true
        out_io.to_s.should eq("true")
      end
    end
  end

  it "resolves every dependent to its declared version in a conflicting topology" do
    It.with_registry do |registry|
      registry.add("dep-a", "2.0.0", It.pkg("dep-a", "2.0.0", dependencies: {"dep-b" => "2.0.0", "dep-c" => "2.0.0"}),
        {"index.js" => "module.exports = {b: require('dep-b'), c: require('dep-c')}"})
      registry.add("dep-b", "1.0.0", It.pkg("dep-b", "1.0.0", dependencies: {"dep-c" => "1.0.0"}),
        {"index.js" => "module.exports = {c: require('dep-c')}"})
      registry.add("dep-b", "2.0.0", It.pkg("dep-b", "2.0.0", dependencies: {"dep-c" => "2.0.0", "dep-d" => "1.0.0"}),
        {"index.js" => "module.exports = {c: require('dep-c'), d: require('dep-d')}"})
      registry.add("dep-c", "1.0.0", It.pkg("dep-c", "1.0.0"), {"index.js" => "module.exports = '1.0.0'"})
      registry.add("dep-c", "2.0.0", It.pkg("dep-c", "2.0.0"), {"index.js" => "module.exports = '2.0.0'"})
      registry.add("dep-d", "1.0.0", It.pkg("dep-d", "1.0.0"), {"index.js" => "module.exports = '1.0.0'"})

      # A@2 -> B@2 -> C@2 + D@1, alongside B@1 -> C@1
      It.install_project(registry, %({"name":"app","version":"1.0.0","dependencies":{"dep-a":"2.0.0","dep-b":"1.0.0"}})) do |project|
        out_io = IO::Memory.new
        err_io = IO::Memory.new
        # Each dependent resolves its own declared versions; the root-level
        # placement of shared packages is layout-dependent, so only the
        # per-dependent resolution is asserted.
        status = Process.run("node", ["-e", "process.stdout.write(JSON.stringify({a: require('dep-a'), b: require('dep-b')}))"],
          chdir: project.to_s, output: out_io, error: err_io)
        status.success?.should be_true, "resolution error: #{err_io.to_s}"
        JSON.parse(out_io.to_s).should eq(JSON.parse(%({"a":{"b":{"c":"2.0.0","d":"1.0.0"},"c":"2.0.0"},"b":{"c":"1.0.0"}})))
      end
    end
  end
end

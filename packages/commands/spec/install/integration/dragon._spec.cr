require "./spec_helper"

# Ports of Yarn's "dragon tests" (packages/pkg-tests/pkg-tests-specs/sources/dragon.js):
# the biggest, most convoluted install topologies that stress the hoisting
# and workspace/peer resolution machinery.
describe "dragon tests", tags: "integration" do
  it "passes dragon test 1 (hoisting merge with a version conflict)" do
    It.with_registry do |registry|
      registry.add("a", "1.0.0", It.pkg("a", "1.0.0"), {"index.js" => "a1"})
      registry.add("b", "1.0.0", It.pkg("b", "1.0.0", dependencies: {"a" => "1.0.0"}), {"index.js" => "b1"})
      registry.add("b", "2.0.0", It.pkg("b", "2.0.0", dependencies: {"a" => "1.0.0"}), {"index.js" => "b2"})
      registry.add("c", "1.0.0", It.pkg("c", "1.0.0", dependencies: {"b" => "1.0.0"}), {"index.js" => "c1"})
      registry.add("d", "1.0.0", It.pkg("d", "1.0.0", dependencies: {"c" => "1.0.0"}), {"index.js" => "d1"})
      registry.add("e", "1.0.0", It.pkg("e", "1.0.0", dependencies: {"b" => "2.0.0", "c" => "1.0.0"}), {"index.js" => "e1"})

      # . -> D@1 -> C@1 -> B@1 -> A@1
      #   -> E@1 -> B@2
      #         -> C@1 -> B@1 -> A@1
      It.install_project(registry, %({"name":"app","version":"1.0.0","dependencies":{"d":"1.0.0","e":"1.0.0"}})) do |project|
        # The shared chain is hoisted once, with the conflicting B version nested
        File.read(project / "node_modules/a/index.js").should eq("a1")
        File.read(project / "node_modules/b/index.js").should eq("b2")
        File.read(project / "node_modules/c/index.js").should eq("c1")
        File.read(project / "node_modules/d/index.js").should eq("d1")
        File.read(project / "node_modules/e/index.js").should eq("e1")

        # C depends on B@1 and resolves its nested copy
        File.read(project / "node_modules/c/node_modules/b/index.js").should eq("b1")
        # B@1's own dependency resolves through the hoisted A at the top level
        File.exists?(project / "node_modules/c/node_modules/b/node_modules/a").should be_false
        # E's B@2 is the hoisted root copy, nothing nested under E
        File.exists?(project / "node_modules/e/node_modules").should be_false
      end
    end
  end

  it "passes dragon test 2 (workspace dependency with a peer)" do
    It.with_registry do |registry|
      registry.add("no-deps", "1.0.0", It.pkg("no-deps", "1.0.0"), {"index.js" => "module.exports = {name: 'no-deps', version: '1.0.0'}"})

      ws_root = Path.new(Dir.tempdir, "zap-ws-test-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(ws_root / "a")
        Dir.mkdir_p(ws_root / "b")
        File.write(ws_root / "package.json", %({"name":"ws-root","version":"1.0.0","workspaces":["a","b"]}))
        File.write(ws_root / ".npmrc", "registry=#{registry.base_url}/\n")
        File.write(ws_root / "a/package.json", %({"name":"a","version":"1.0.0","dependencies":{"b":"1.0.0","no-deps":"1.0.0"}}))
        File.write(ws_root / "a/index.js", "module.exports = require('b')")
        File.write(ws_root / "b/package.json", %({"name":"b","version":"1.0.0","peerDependencies":{"no-deps":"*"}}))
        File.write(ws_root / "b/index.js", "module.exports = require('no-deps')")

        config = Core::Config.new.copy_with(prefix: ws_root.to_s, store_path: (ws_root / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: false)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)

        # A requires B, and B's peer is satisfied by A's dependency at the root
        out_io = IO::Memory.new
        err_io = IO::Memory.new
        status = Process.run("node", ["-e", "process.stdout.write(JSON.stringify(require('b')))"], chdir: (ws_root / "a").to_s, output: out_io, error: err_io)
        status.success?.should be_true
        out_io.to_s.should eq(%({"name":"no-deps","version":"1.0.0"}))
      ensure
        FileUtils.rm_rf(ws_root)
      end
    end
  end
end

require "./spec_helper"

# The engines field: zap warns on unsatisfied engine requirements by
# default (npm/pnpm/yarn parity) and fails the install with
# --engine-strict (berry parity).
describe "engines", tags: "integration" do
  it "warns but installs when the engine is not satisfied" do
    It.with_registry do |registry|
      registry.add("needs-node", "1.0.0", It.pkg("needs-node", "1.0.0", engines: {"node" => ">=99.0.0"}), {"index.js" => "n"})

      It.install_project(registry, %({"name":"app","version":"1.0.0","dependencies":{"needs-node":"1.0.0"}})) do |project|
        File.read(project / "node_modules/needs-node/index.js").should eq("n")
      end
    end
  end

  it "fails the install with --engine-strict when the engine is not satisfied" do
    It.with_registry do |registry|
      registry.add("needs-node", "1.0.0", It.pkg("needs-node", "1.0.0", engines: {"node" => ">=99.0.0"}), {"index.js" => "n"})

      ic = Commands::Install::Config.new.copy_with(engine_strict: true)
      expect_raises(Exception, /engine mismatch|needs-node/) do
        It.install_project(registry, %({"name":"app","version":"1.0.0","dependencies":{"needs-node":"1.0.0"}}), install_config: ic) { }
      end
    end
  end

  it "installs normally when the engine is satisfied" do
    It.with_registry do |registry|
      registry.add("ok-node", "1.0.0", It.pkg("ok-node", "1.0.0", engines: {"node" => ">=6"}), {"index.js" => "o"})

      ic = Commands::Install::Config.new.copy_with(engine_strict: true)
      It.install_project(registry, %({"name":"app","version":"1.0.0","dependencies":{"ok-node":"1.0.0"}}), install_config: ic) do |project|
        File.read(project / "node_modules/ok-node/index.js").should eq("o")
      end
    end
  end
  it "tolerates malformed engines metadata (engines published as an array)" do
    It.with_registry do |registry|
      # ansi-html-community@0.0.8 publishes `"engines": ["node >= 0.8.0"]`
      manifest = It.pkg("weird-engines", "1.0.0").merge({"engines" => JSON.parse(%(["node >= 0.8.0"]))})
      registry.add("weird-engines", "1.0.0", manifest, {"index.js" => "w"})
      It.install_project(registry, %({"name":"app","version":"1.0.0","dependencies":{"weird-engines":"^1.0.0"}})) do |project|
        File.read(project / "node_modules/weird-engines/index.js").should eq("w")
      end
    end
  end

  it "tolerates malformed os metadata (os published as a string)" do
    It.with_registry do |registry|
      manifest = It.pkg("weird-os", "1.0.0").merge({"os" => JSON.parse(%("linux"))})
      registry.add("weird-os", "1.0.0", manifest, {"index.js" => "o"})
      It.install_project(registry, %({"name":"app","version":"1.0.0","dependencies":{"weird-os":"^1.0.0"}})) do |project|
        File.read(project / "node_modules/weird-os/index.js").should eq("o")
      end
    end
  end

end

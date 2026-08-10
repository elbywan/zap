require "./spec_helper"

# Additional install strategies: classic_shallow keeps transitive
# dependencies nested instead of hoisting them to the top level.
describe "install strategies extra", tags: "integration" do
  it "nests transitive dependencies with the classic_shallow strategy" do
    It.with_registry do |registry|
      registry.add("b", "1.0.0", It.pkg("b", "1.0.0"), {"index.js" => "b"})
      registry.add("a", "1.0.0", It.pkg("a", "1.0.0", dependencies: {"b" => "1.0.0"}), {"index.js" => "a"})

      ic = Commands::Install::Config.new.copy_with(strategy: Data::Package::InstallStrategy::Classic_Shallow)
      It.install_project(registry, %({"name":"app","version":"1.0.0","dependencies":{"a":"1.0.0"}}), install_config: ic) do |project|
        File.read(project / "node_modules/a/index.js").should eq("a")
        # b is not hoisted to the root; it nests under its parent
        File.exists?(project / "node_modules/b").should be_false
        File.read(project / "node_modules/a/node_modules/b/index.js").should eq("b")
      end
    end
  end

  it "shares a hoisted dependency across siblings with classic_shallow" do
    It.with_registry do |registry|
      registry.add("shared", "1.0.0", It.pkg("shared", "1.0.0"), {"index.js" => "s"})
      registry.add("x", "1.0.0", It.pkg("x", "1.0.0", dependencies: {"shared" => "1.0.0"}), {"index.js" => "x"})
      registry.add("y", "1.0.0", It.pkg("y", "1.0.0", dependencies: {"shared" => "1.0.0"}), {"index.js" => "y"})

      ic = Commands::Install::Config.new.copy_with(strategy: Data::Package::InstallStrategy::Classic_Shallow)
      It.install_project(registry, %({"name":"app","version":"1.0.0","dependencies":{"x":"1.0.0","y":"1.0.0"}}), install_config: ic) do |project|
        # Both parents nest the shared dep under themselves
        File.read(project / "node_modules/x/node_modules/shared/index.js").should eq("s")
        File.read(project / "node_modules/y/node_modules/shared/index.js").should eq("s")
      end
    end
  end
end

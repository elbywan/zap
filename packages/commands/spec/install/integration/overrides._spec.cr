require "./spec_helper"


# Override behaviors, mirroring yarn's and npm's override semantics:
# global, parent-scoped (npm "a@1": {"c": "2.0.0"}) and range overrides.
describe "overrides", tags: "integration" do
  it "applies a global override to a transitive dependency" do
    It.with_registry do |registry|
      registry.add("dep", "1.0.0", It.pkg("dep", "1.0.0"), {"index.js" => "1.0.0"})
      registry.add("dep", "2.0.0", It.pkg("dep", "2.0.0"), {"index.js" => "2.0.0"})
      registry.add("parent", "1.0.0", It.pkg("parent", "1.0.0", dependencies: {"dep" => "^1.0.0"}), {"index.js" => "parent"})

      It.install_project(
        registry,
        %({"name":"app","version":"1.0.0","dependencies":{"parent":"1.0.0"},"overrides":{"dep":"2.0.0"}})
      ) do |project|
        File.read(project / "node_modules/dep/index.js").should eq("2.0.0")
      end
    end
  end

  it "applies a parent-scoped override" do
    It.with_registry do |registry|
      registry.add("dep", "1.0.0", It.pkg("dep", "1.0.0"), {"index.js" => "1.0.0"})
      registry.add("dep", "2.0.0", It.pkg("dep", "2.0.0"), {"index.js" => "2.0.0"})
      registry.add("parent", "1.0.0", It.pkg("parent", "1.0.0", dependencies: {"dep" => "^1.0.0"}), {"index.js" => "parent"})

      It.install_project(
        registry,
        %({"name":"app","version":"1.0.0","dependencies":{"parent":"1.0.0"},"overrides":{"parent@1":{"dep":"2.0.0"}}})
      ) do |project|
        File.read(project / "node_modules/dep/index.js").should eq("2.0.0")
      end
    end
  end

  it "does not apply a parent-scoped override to a different parent" do
    It.with_registry do |registry|
      registry.add("dep", "1.0.0", It.pkg("dep", "1.0.0"), {"index.js" => "1.0.0"})
      registry.add("dep", "2.0.0", It.pkg("dep", "2.0.0"), {"index.js" => "2.0.0"})
      registry.add("parent", "1.0.0", It.pkg("parent", "1.0.0", dependencies: {"dep" => "^1.0.0"}), {"index.js" => "parent"})
      registry.add("other", "1.0.0", It.pkg("other", "1.0.0", dependencies: {"dep" => "^1.0.0"}), {"index.js" => "other"})

      It.install_project(
        registry,
        %({"name":"app","version":"1.0.0","dependencies":{"parent":"1.0.0","other":"1.0.0"},"overrides":{"other@1":{"dep":"2.0.0"}}})
      ) do |project|
        # The override only applies to "other": the parent still resolves dep@1
        # (nested), while the overridden copy is hoisted to the root
        File.read(project / "node_modules/parent/node_modules/dep/index.js").should eq("1.0.0")
        Dir.glob(project / "node_modules/**/dep/index.js").map { |p| File.read(p) }.should contain("2.0.0")
      end
    end
  end

  it "applies a range override" do
    It.with_registry do |registry|
      registry.add("dep", "1.0.0", It.pkg("dep", "1.0.0"), {"index.js" => "1.0.0"})
      registry.add("dep", "2.1.0", It.pkg("dep", "2.1.0"), {"index.js" => "2.1.0"})
      registry.add("parent", "1.0.0", It.pkg("parent", "1.0.0", dependencies: {"dep" => "^1.0.0"}), {"index.js" => "parent"})

      It.install_project(
        registry,
        %({"name":"app","version":"1.0.0","dependencies":{"parent":"1.0.0"},"overrides":{"dep":"^2.0.0"}})
      ) do |project|
        File.read(project / "node_modules/dep/index.js").should eq("2.1.0")
      end
    end
  end
end

require "./spec_helper"


# Hoisting and deduplication behaviors (the "dragon" scenarios from yarn's
# fixtures): diamond dependencies and deep chains.
describe "hoisting", tags: "integration" do
  it "hoists a deep dependency chain" do
    It.with_registry do |registry|
      registry.add("d", "1.0.0", It.pkg("d", "1.0.0"), {"index.js" => "d"})
      registry.add("c", "1.0.0", It.pkg("c", "1.0.0", dependencies: {"d" => "1.0.0"}), {"index.js" => "c"})
      registry.add("b", "1.0.0", It.pkg("b", "1.0.0", dependencies: {"c" => "1.0.0"}), {"index.js" => "b"})
      registry.add("a", "1.0.0", It.pkg("a", "1.0.0", dependencies: {"b" => "1.0.0"}), {"index.js" => "a"})

      It.install_project(registry, %({"name":"app","version":"1.0.0","dependencies":{"a":"1.0.0"}})) do |project|
        # All deduplicated to the root
        File.exists?(project / "node_modules/a/index.js").should be_true
        File.exists?(project / "node_modules/b/index.js").should be_true
        File.exists?(project / "node_modules/c/index.js").should be_true
        File.exists?(project / "node_modules/d/index.js").should be_true
      end
    end
  end

  it "nests a conflicting version in a diamond" do
    It.with_registry do |registry|
      registry.add("shared", "1.0.0", It.pkg("shared", "1.0.0"), {"index.js" => "1.0.0"})
      registry.add("shared", "2.0.0", It.pkg("shared", "2.0.0"), {"index.js" => "2.0.0"})
      registry.add("left", "1.0.0", It.pkg("left", "1.0.0", dependencies: {"shared" => "1.0.0"}), {"index.js" => "left"})
      registry.add("right", "1.0.0", It.pkg("right", "1.0.0", dependencies: {"shared" => "2.0.0"}), {"index.js" => "right"})

      It.install_project(
        registry,
        %({"name":"app","version":"1.0.0","dependencies":{"left":"1.0.0","right":"1.0.0"}})
      ) do |project|
        # One version is hoisted, the other is nested; both must be resolvable
        root = File.read(project / "node_modules/shared/index.js")
        nested = Dir.glob(project / "node_modules/{left,right}/node_modules/shared/index.js").map { |p| File.read(p) }
        [root].concat(nested).sort.should eq(["1.0.0", "2.0.0"])
      end
    end
  end

  it "shares a hoisted dependency across siblings" do
    It.with_registry do |registry|
      registry.add("shared", "1.0.0", It.pkg("shared", "1.0.0"), {"index.js" => "1.0.0"})
      registry.add("left", "1.0.0", It.pkg("left", "1.0.0", dependencies: {"shared" => "1.0.0"}), {"index.js" => "left"})
      registry.add("right", "1.0.0", It.pkg("right", "1.0.0", dependencies: {"shared" => "1.0.0"}), {"index.js" => "right"})

      It.install_project(
        registry,
        %({"name":"app","version":"1.0.0","dependencies":{"left":"1.0.0","right":"1.0.0"}})
      ) do |project|
        # Only one copy of the shared dependency, at the root
        File.exists?(project / "node_modules/shared/index.js").should be_true
        Dir.glob(project / "node_modules/{left,right}/node_modules/shared").size.should eq(0)
      end
    end
  end
end

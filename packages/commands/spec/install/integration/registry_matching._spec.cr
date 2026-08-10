require "./spec_helper"

# Registry metadata matching: cpu field mismatches skip the package like
# npm/yarn, and aliases can target a version range.
describe "registry matching", tags: "integration" do
  it "skips packages with a non-matching cpu field" do
    It.with_registry do |registry|
      registry.add("arch-dep", "1.0.0", It.pkg("arch-dep", "1.0.0", cpu: ["arm64"]), {"index.js" => "arm-only"})
      registry.add("arch-ok", "1.0.0", It.pkg("arch-ok", "1.0.0", cpu: ["x64"]), {"index.js" => "x64"})

      It.install_project(registry, %({"name":"app","version":"1.0.0","dependencies":{"arch-dep":"1.0.0","arch-ok":"1.0.0"}})) do |project|
        File.exists?(project / "node_modules/arch-dep").should be_false
        File.read(project / "node_modules/arch-ok/index.js").should eq("x64")
      end
    end
  end

  it "installs an alias targeting a range" do
    It.with_registry do |registry|
      registry.add("real-pkg", "1.0.0", It.pkg("real-pkg", "1.0.0"), {"index.js" => "1.0.0"})
      registry.add("real-pkg", "1.5.0", It.pkg("real-pkg", "1.5.0"), {"index.js" => "1.5.0"})

      It.install_project(registry, %({"name":"app","version":"1.0.0","dependencies":{"my-alias":"npm:real-pkg@^1.0.0"}})) do |project|
        File.read(project / "node_modules/my-alias/index.js").should eq("1.5.0")
        File.exists?(project / "node_modules/real-pkg").should be_false
      end
    end
  end
end

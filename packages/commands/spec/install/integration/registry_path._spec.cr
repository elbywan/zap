require "./spec_helper"

describe "registry base paths", tags: "integration" do
  it "installs from a registry served under a path prefix" do
    It.with_registry(prefix: "npm") do |registry|
      registry.add("path-pkg", "1.0.0", It.pkg("path-pkg", "1.0.0"), {"index.js" => "path"})
      It.install_project(registry, %({"name":"app","version":"1.0.0","dependencies":{"path-pkg":"1.0.0"}})) do |project|
        File.read(project / "node_modules/path-pkg/index.js").should eq("path")
      end
    end
  end
end

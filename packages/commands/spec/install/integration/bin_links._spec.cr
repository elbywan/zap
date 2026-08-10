require "./spec_helper"

# Ports of yarn classic's bin-links tests (__tests__/commands/install/bin-links.js):
# bin-name conflicts between direct and transitive dependencies, and empty
# bin strings.
describe "bin links edge cases", tags: "integration" do
  it "gives a direct dependency's bin priority over a transitive one" do
    It.with_registry do |registry|
      registry.add("tool-a", "1.0.0", It.pkg("tool-a", "1.0.0", extra: {"bin" => Zap::Integration.json({"shared" => "shared.js"})}),
        {"shared.js" => "#!/usr/bin/env node\nprocess.stdout.write('A')"})
      registry.add("tool-b", "1.0.0", It.pkg("tool-b", "1.0.0", extra: {"bin" => Zap::Integration.json({"shared" => "shared.js"})}),
        {"shared.js" => "#!/usr/bin/env node\nprocess.stdout.write('B')"})
      registry.add("mid", "1.0.0", It.pkg("mid", "1.0.0", dependencies: {"tool-b" => "1.0.0"}), {"index.js" => "m"})

      It.install_project(registry, %({"name":"app","version":"1.0.0","dependencies":{"tool-a":"1.0.0","mid":"1.0.0"}})) do |project|
        bin = project / "node_modules/.bin/shared"
        # The direct dependency wins the conflicting bin name
        File.symlink?(bin).should be_true
        out_io = IO::Memory.new
        status = Process.run("node", [bin.to_s], output: out_io)
        status.success?.should be_true
        out_io.to_s.should eq("A")
      end
    end
  end

  it "does not link an empty bin string" do
    It.with_registry do |registry|
      registry.add("no-bin", "1.0.0", It.pkg("no-bin", "1.0.0", bin: ""), {"index.js" => "n"})

      It.install_project(registry, %({"name":"app","version":"1.0.0","dependencies":{"no-bin":"1.0.0"}})) do |project|
        File.exists?(project / "node_modules/.bin/no-bin").should be_false
      end
    end
  end
end

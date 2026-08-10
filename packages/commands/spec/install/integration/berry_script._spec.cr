require "../../../exec/exec"
require "../../../exec/config"
require "./spec_helper"

# Ports of yarn berry's script tests (pkg-tests-specs/sources/script.js):
# dependency binaries resolvable from other cwds, binaries requiring their
# own dependencies and relative paths, and install scripts running the
# binaries exposed by their own dependencies.
describe "berry script ports", tags: "integration" do
  it "executes a dependency binary from a subdirectory of the project" do
    It.with_registry do |registry|
      registry.add("with-bin", "1.0.0", It.pkg("with-bin", "1.0.0", bin: "cli.js"), {"index.js" => "main", "cli.js" => "#!/usr/bin/env node\nrequire('fs').writeFileSync('bin-ran.txt', 'ok')"})

      It.install_project(registry, %({"name":"app","version":"1.0.0","dependencies":{"with-bin":"1.0.0"}})) do |project|
        subdir = project / "src"
        Dir.mkdir_p(subdir)
        exec_config = Core::Config.new.copy_with(prefix: subdir.to_s, silent: true)
        Commands::Exec.run(exec_config, Commands::Exec::Config.new(command: "with-bin"))
        File.read(project / "bin-ran.txt").should eq("ok")
      end
    end
  end

  it "lets a dependency binary require its own dependencies and relative paths" do
    It.with_registry do |registry|
      registry.add("bin-dep", "1.0.0", It.pkg("bin-dep", "1.0.0"), {"index.js" => "module.exports = 'from-bin-dep'"})
      registry.add("with-bin", "1.0.0", It.pkg("with-bin", "1.0.0", bin: "cli.js", dependencies: {"bin-dep" => "1.0.0"}),
        {"index.js" => "main",
         "cli.js" => "#!/usr/bin/env node\nconst dep = require('bin-dep'); const helper = require('./lib/helper'); require('fs').writeFileSync('bin-ran.txt', dep + '+' + helper)",
         "lib/helper.js" => "module.exports = 'helper'"})

      It.install_project(registry, %({"name":"app","version":"1.0.0","dependencies":{"with-bin":"1.0.0"}})) do |project|
        exec_config = Core::Config.new.copy_with(prefix: project.to_s, silent: true)
        Commands::Exec.run(exec_config, Commands::Exec::Config.new(command: "with-bin"))
        File.read(project / "bin-ran.txt").should eq("from-bin-dep+helper")
      end
    end
  end

  it "lets an install script run the binaries exposed by its own dependencies" do
    It.with_registry do |registry|
      registry.add("tool-bin", "1.0.0", It.pkg("tool-bin", "1.0.0", bin: "tool.js"), {"tool.js" => "#!/usr/bin/env node\nrequire('fs').writeFileSync('tool-ran.txt', 'tool')"})
      registry.add("scripted", "1.0.0", It.pkg("scripted", "1.0.0", dependencies: {"tool-bin" => "1.0.0"},
        scripts: {"postinstall" => "tool-bin"}),
        {"index.js" => "s"})

      It.install_project(registry, %({"name":"app","version":"1.0.0","dependencies":{"scripted":"1.0.0"}})) do |project|
        File.read(project / "node_modules/scripted/tool-ran.txt").should eq("tool")
      end
    end
  end
end

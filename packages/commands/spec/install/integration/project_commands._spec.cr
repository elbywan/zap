require "../../../exec/exec"
require "../../../exec/config"
require "../../../init/init"
require "../../../init/config"
require "../../../rebuild/rebuild"
require "../../../rebuild/config"
require "../../../run/run"
require "../../../run/config"
require "./spec_helper"

# Project lifecycle commands: init scaffolds a package.json, rebuild
# re-runs lifecycle scripts, and run executes package.json scripts.
CMD_MARKER_SCRIPT = %(node -e "require('fs').appendFileSync('order.txt', process.argv[1])")

describe "project commands", tags: "integration" do
  it "initializes a package.json with --yes" do
    tmpdir = Path.new(Dir.tempdir, "zap-init-#{Random::Secure.hex(4)}")
    begin
      Dir.mkdir_p(tmpdir)
      config = Core::Config.new.copy_with(prefix: tmpdir.to_s, silent: true)
      Dir.cd(tmpdir) do
        Commands::Init.run(config, Commands::Init::Config.new.copy_with(yes: true))
      end

      pkg = JSON.parse(File.read(tmpdir / "package.json"))
      pkg["name"].as_s.should eq(Path.new(tmpdir).basename)
      pkg["version"].as_s.should eq("0.0.1")
      pkg["main"].as_s.should eq("index.js")
      pkg["license"].as_s.should eq("ISC")
    ensure
      FileUtils.rm_rf(tmpdir)
    end
  end

  it "rebuild re-runs lifecycle scripts of installed packages" do
    It.with_registry do |registry|
      registry.add("scripted", "1.0.0", It.pkg("scripted", "1.0.0",
        scripts: {"install" => %(#{CMD_MARKER_SCRIPT} x)}),
        {"index.js" => "s", "binding.gyp" => ""})

      It.install_project(registry, %({"name":"app","version":"1.0.0","dependencies":{"scripted":"1.0.0"}})) do |project|
        marker = project / "node_modules/scripted/order.txt"
        File.read(marker).should eq("x")

        old_argv = ARGV.dup
        begin
          ARGV.replace([] of String)
          rebuild_config = Core::Config.new.copy_with(prefix: project.to_s, silent: true)
          Commands::Rebuild.run(rebuild_config, Commands::Rebuild::Config.new)
        ensure
          ARGV.replace(old_argv)
        end
        File.read(marker).should eq("xx")
      end
    end
  end

  it "run executes a package.json script" do
    tmpdir = Path.new(Dir.tempdir, "zap-run-#{Random::Secure.hex(4)}")
    begin
      Dir.mkdir_p(tmpdir)
      File.write(tmpdir / "package.json", %({"name":"app","version":"1.0.0","scripts":{"hello":"node -e \\"require('fs').writeFileSync('ran.txt','ok')\\""}}))

      run_config = Core::Config.new.copy_with(prefix: tmpdir.to_s, silent: true)
      Commands::Run.run(run_config, Commands::Run::Config.new.copy_with(script: "hello"))

      File.read(tmpdir / "ran.txt").should eq("ok")
    ensure
      FileUtils.rm_rf(tmpdir)
    end
  end
end

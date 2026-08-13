require "./spec_helper"


# Lifecycle script behaviors under the strict-by-default policy (pnpm v10
# parity): dependency scripts do not run unless the package is allowlisted via
# zap.only_built_dependencies, --ignore-scripts skips everything including the
# root project, and a failing allowlisted script fails the install.
MARKER_SCRIPT = %(node -e "require('fs').appendFileSync('order.txt', process.argv[1])")

describe "lifecycle scripts", tags: "integration" do

  it "does not run dependency scripts by default" do
    It.with_registry do |registry|
      registry.add("scripted", "1.0.0", It.pkg("scripted", "1.0.0",
        scripts: {"install" => %(#{MARKER_SCRIPT} install)}),
        {"index.js" => "s"})

      It.install_project(registry, %({"name":"app","version":"1.0.0","dependencies":{"scripted":"1.0.0"}})) do |project|
        File.exists?(project / "node_modules/scripted/order.txt").should be_false
      end
    end
  end

  it "runs scripts for allowlisted packages in order" do
    It.with_registry do |registry|
      registry.add("scripted", "1.0.0", It.pkg("scripted", "1.0.0",
        scripts: {"preinstall" => %(#{MARKER_SCRIPT} pre), "install" => %(#{MARKER_SCRIPT} install), "postinstall" => %(#{MARKER_SCRIPT} post)}),
        {"index.js" => "s"})

      It.install_project(registry, %({"name":"app","version":"1.0.0","dependencies":{"scripted":"1.0.0"},"zap":{"only_built_dependencies":["scripted"]}})) do |project|
        marker = project / "node_modules/scripted/order.txt"
        File.read(marker).should eq("preinstallpost")
      end
    end
  end

  it "skips scripts with --ignore-scripts" do
    It.with_registry do |registry|
      registry.add("scripted", "1.0.0", It.pkg("scripted", "1.0.0",
        scripts: {"install" => %(#{MARKER_SCRIPT} install)}),
        {"index.js" => "s"})

      ic = Commands::Install::Config.new.copy_with(ignore_scripts: true)
      It.install_project(registry, %({"name":"app","version":"1.0.0","dependencies":{"scripted":"1.0.0"},"zap":{"only_built_dependencies":["scripted"]}}), install_config: ic) do |project|
        File.exists?(project / "node_modules/scripted/order.txt").should be_false
      end
    end
  end

  it "fails the install when an allowlisted script fails" do
    It.with_registry do |registry|
      registry.add("broken-script", "1.0.0", It.pkg("broken-script", "1.0.0",
        scripts: {"install" => "node -e \"process.exit(1)\""}),
        {"index.js" => "b"})

      raised = false
      begin
        It.install_project(registry, %({"name":"app","version":"1.0.0","dependencies":{"broken-script":"1.0.0"},"zap":{"only_built_dependencies":["broken-script"]}})) { |_| }
      rescue ex
        raised = true
        ex.message.not_nil!.should contain("broken-script")
      end
      raised.should be_true
    end
  end

  it "runs all scripts with dangerously_allow_all_builds" do
    It.with_registry do |registry|
      registry.add("scripted", "1.0.0", It.pkg("scripted", "1.0.0",
        scripts: {"install" => %(#{MARKER_SCRIPT} install)}),
        {"index.js" => "s"})

      It.install_project(registry, %({"name":"app","version":"1.0.0","dependencies":{"scripted":"1.0.0"},"zap":{"dangerously_allow_all_builds":true}})) do |project|
        File.exists?(project / "node_modules/scripted/order.txt").should be_true
      end
    end
  end

  it "warns about ignored build scripts" do
    It.with_registry do |registry|
      registry.add("scripted", "1.0.0", It.pkg("scripted", "1.0.0",
        scripts: {"install" => %(#{MARKER_SCRIPT} install)}),
        {"index.js" => "s"})

      tmpdir = Path.new(Dir.tempdir, "zap-it-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(tmpdir)
        File.write(tmpdir / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"scripted":"1.0.0"}}))
        File.write(tmpdir / ".npmrc", "registry=#{registry.base_url}/\n")
        config = Core::Config.new.copy_with(prefix: tmpdir.to_s, store_path: (tmpdir / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: false)
        out_io = IO::Memory.new
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Plain.new(out_io))
        out_io.to_s.should contain("Ignored build scripts")
        out_io.to_s.should contain("scripted@1.0.0")
        File.exists?(tmpdir / "node_modules/scripted/order.txt").should be_false
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end

  it "suppresses the warning for ignored_built_dependencies" do
    It.with_registry do |registry|
      registry.add("scripted", "1.0.0", It.pkg("scripted", "1.0.0",
        scripts: {"install" => %(#{MARKER_SCRIPT} install)}),
        {"index.js" => "s"})

      tmpdir = Path.new(Dir.tempdir, "zap-it-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(tmpdir)
        File.write(tmpdir / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"scripted":"1.0.0"},"zap":{"ignored_built_dependencies":["scripted"]}}))
        File.write(tmpdir / ".npmrc", "registry=#{registry.base_url}/\n")
        config = Core::Config.new.copy_with(prefix: tmpdir.to_s, store_path: (tmpdir / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: false)
        out_io = IO::Memory.new
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Plain.new(out_io))
        out_io.to_s.should_not contain("Ignored build scripts")
        File.exists?(tmpdir / "node_modules/scripted/order.txt").should be_false
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end

  it "runs the root project's own install scripts" do
    It.with_registry do |registry|
      registry.add("a", "1.0.0", It.pkg("a", "1.0.0"), {"index.js" => "a"})

      It.install_project(registry, %({"name":"app","version":"1.0.0","dependencies":{"a":"1.0.0"},"scripts":{"postinstall":"touch root-marker.txt"}})) do |project|
        File.exists?(project / "root-marker.txt").should be_true
      end
    end
  end
end

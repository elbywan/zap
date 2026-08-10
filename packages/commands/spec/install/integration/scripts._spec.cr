require "./spec_helper"


# Lifecycle script behaviors, mirroring npm/yarn: preinstall/install/postinstall
# run in order for newly installed packages, --ignore-scripts skips them, and a
# failing script fails the install.
MARKER_SCRIPT = %(node -e "require('fs').appendFileSync('order.txt', process.argv[1])")

describe "lifecycle scripts", tags: "integration" do

  it "runs install scripts in order" do
    It.with_registry do |registry|
      registry.add("scripted", "1.0.0", It.pkg("scripted", "1.0.0",
        scripts: {"preinstall" => %(#{MARKER_SCRIPT} pre), "install" => %(#{MARKER_SCRIPT} install), "postinstall" => %(#{MARKER_SCRIPT} post)}),
        {"index.js" => "s"})

      It.install_project(registry, %({"name":"app","version":"1.0.0","dependencies":{"scripted":"1.0.0"}})) do |project|
        marker = project / "node_modules/scripted/order.txt"
        File.exists?(marker).should be_true
        File.read(marker).should eq("preinstallpost")
      end
    end
  end

  it "skips scripts with --ignore-scripts" do
    It.with_registry do |registry|
      registry.add("scripted", "1.0.0", It.pkg("scripted", "1.0.0",
        scripts: {"preinstall" => %(#{MARKER_SCRIPT} pre), "install" => %(#{MARKER_SCRIPT} install), "postinstall" => %(#{MARKER_SCRIPT} post)}),
        {"index.js" => "s"})

      ic = Commands::Install::Config.new.copy_with(ignore_scripts: true)
      It.install_project(registry, %({"name":"app","version":"1.0.0","dependencies":{"scripted":"1.0.0"}}), install_config: ic) do |project|
        File.exists?(project / "node_modules/scripted/order.txt").should be_false
      end
    end
  end

  it "fails the install when an install script fails" do
    It.with_registry do |registry|
      registry.add("broken-script", "1.0.0", It.pkg("broken-script", "1.0.0",
        scripts: {"install" => "node -e \"process.exit(1)\""}),
        {"index.js" => "b"})

      raised = false
      begin
        It.install_project(registry, %({"name":"app","version":"1.0.0","dependencies":{"broken-script":"1.0.0"}})) do |project|
        end
      rescue ex
        raised = true
        ex.message.not_nil!.should contain("broken-script")
      end
      raised.should be_true
    end
  end
end

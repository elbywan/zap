require "../../../why/why"
require "../../../why/config"
require "./spec_helper"


# Command round-trips: zap remove prunes the tree and the package.json,
# zap why reports the dependents of a package.
describe "commands", tags: "integration" do
  it "removes a dependency and updates package.json" do
    It.with_registry do |registry|
      registry.add("b", "1.0.0", It.pkg("b", "1.0.0"), {"index.js" => "b"})
      registry.add("a", "1.0.0", It.pkg("a", "1.0.0"), {"index.js" => "a"})

      tmpdir = Path.new(Dir.tempdir, "zap-it-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(tmpdir)
        File.write(tmpdir / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"a":"1.0.0","b":"1.0.0"}}))
        File.write(tmpdir / ".npmrc", "registry=#{registry.base_url}/\n")
        config = Core::Config.new.copy_with(prefix: tmpdir.to_s, store_path: (tmpdir / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)
        File.exists?(tmpdir / "node_modules/a/index.js").should be_true

        remove_ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true, removed_packages: ["b"])
        Commands::Install.run(config, remove_ic, raise_on_failure: true, reporter: Reporter::Null.new)

        # The removed dependency is pruned from node_modules and package.json
        File.exists?(tmpdir / "node_modules/b").should be_false
        pkg_json = JSON.parse(File.read(tmpdir / "package.json"))
        pkg_json["dependencies"].as_h.has_key?("b").should be_false
        pkg_json["dependencies"].as_h.has_key?("a").should be_true
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end

  it "reports why a package is installed" do
    It.with_registry do |registry|
      registry.add("b", "1.0.0", It.pkg("b", "1.0.0"), {"index.js" => "b"})
      registry.add("a", "1.0.0", It.pkg("a", "1.0.0", dependencies: {"b" => "1.0.0"}), {"index.js" => "a"})

      tmpdir = Path.new(Dir.tempdir, "zap-it-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(tmpdir)
        File.write(tmpdir / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"a":"1.0.0"}}))
        File.write(tmpdir / ".npmrc", "registry=#{registry.base_url}/\n")
        config = Core::Config.new.copy_with(prefix: tmpdir.to_s, store_path: (tmpdir / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)

        old_argv = ARGV.dup
        output = IO::Memory.new
        begin
          ARGV.replace(["b"])
          Commands::Why.run(config, Commands::Why::Config.new, output_io: output)
        ensure
          ARGV.replace(old_argv)
        end
        # The why output mentions the ancestor chain a -> b
        output.to_s.should contain("a")
        output.to_s.should contain("b")
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end
end

require "./spec_helper"


# Lockfile behaviors: stable output across reinstalls, frozen-lockfile
# enforcement, and pinned versions.
describe "lockfile", tags: "integration" do
  it "produces a byte-identical lockfile on reinstall" do
    It.with_registry do |registry|
      registry.add("b", "1.0.0", It.pkg("b", "1.0.0"), {"index.js" => "b"})
      registry.add("a", "1.0.0", It.pkg("a", "1.0.0", dependencies: {"b" => "^1.0.0"}), {"index.js" => "a"})

      tmpdir = Path.new(Dir.tempdir, "zap-it-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(tmpdir)
        File.write(tmpdir / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"a":"1.0.0"}}))
        File.write(tmpdir / ".npmrc", "registry=#{registry.base_url}/\n")
        config = Core::Config.new.copy_with(prefix: tmpdir.to_s, store_path: (tmpdir / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)
        first = File.read(tmpdir / "zap.lock")

        FileUtils.rm_rf(tmpdir / "node_modules")
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)
        File.read(tmpdir / "zap.lock").should eq(first)
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end

  it "fails a frozen install when package.json changed" do
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

        # Change the dependency set without updating the lockfile
        File.write(tmpdir / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"a":"1.0.0","b":"1.0.0"}}))
        frozen = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: true, save: true)
        raised = false
        begin
          Commands::Install.run(config, frozen, raise_on_failure: true, reporter: Reporter::Null.new)
        rescue ex
          raised = true
          ex.message.not_nil!.should contain("frozen-lockfile")
        end
        raised.should be_true
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end

  it "pins the resolved versions in the lockfile" do
    It.with_registry do |registry|
      registry.add("pinned", "1.5.0", It.pkg("pinned", "1.5.0"), {"index.js" => "1.5.0"})
      registry.add("pinned", "1.9.0", It.pkg("pinned", "1.9.0"), {"index.js" => "1.9.0"})

      tmpdir = Path.new(Dir.tempdir, "zap-it-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(tmpdir)
        File.write(tmpdir / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"pinned":"^1.0.0"}}))
        File.write(tmpdir / ".npmrc", "registry=#{registry.base_url}/\n")
        config = Core::Config.new.copy_with(prefix: tmpdir.to_s, store_path: (tmpdir / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)

        lock = Data::Lockfile.new(tmpdir)
        lock.packages["pinned@1.9.0"].should_not be_nil
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end
end

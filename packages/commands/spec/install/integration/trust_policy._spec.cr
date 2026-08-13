require "./spec_helper"

# pnpm's trustPolicy: with no-downgrade, a version whose trust evidence is
# weaker than the strongest evidence of the previously locked versions is
# refused, so a publisher signature or provenance attestation cannot
# silently disappear on an update.
describe "trust policy", tags: "integration" do
  it "refuses a version with weaker trust evidence" do
    It.with_registry do |registry|
      registry.add("trusted", "1.0.0", It.pkg("trusted", "1.0.0"), {"index.js" => "1.0.0"}, signature: true)

      tmpdir = Path.new(Dir.tempdir, "zap-it-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(tmpdir)
        File.write(tmpdir / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"trusted":"^1.0.0"},"zap":{"trust_policy":"no-downgrade"}}))
        File.write(tmpdir / ".npmrc", "registry=#{registry.base_url}/\n")
        config = Core::Config.new.copy_with(prefix: tmpdir.to_s, store_path: (tmpdir / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)

        # The new version drops the publisher signature
        registry.add("trusted", "2.0.0", It.pkg("trusted", "2.0.0"), {"index.js" => "2.0.0"})
        latest = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true, update_all: true, update_latest: true)
        raised = false
        begin
          Commands::Install.run(config, latest, raise_on_failure: true, reporter: Reporter::Null.new)
        rescue ex
          raised = true
          ex.message.not_nil!.should contain("no-downgrade")
          ex.message.not_nil!.should contain("trusted")
        end
        raised.should be_true
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end

  it "allows the same or stronger evidence" do
    It.with_registry do |registry|
      registry.add("trusted", "1.0.0", It.pkg("trusted", "1.0.0"), {"index.js" => "1.0.0"}, signature: true)

      tmpdir = Path.new(Dir.tempdir, "zap-it-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(tmpdir)
        File.write(tmpdir / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"trusted":"^1.0.0"},"zap":{"trust_policy":"no-downgrade"}}))
        File.write(tmpdir / ".npmrc", "registry=#{registry.base_url}/\n")
        config = Core::Config.new.copy_with(prefix: tmpdir.to_s, store_path: (tmpdir / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)

        # The new version keeps the signature: no downgrade
        registry.add("trusted", "2.0.0", It.pkg("trusted", "2.0.0"), {"index.js" => "2.0.0"}, signature: true)
        latest = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true, update_all: true, update_latest: true)
        Commands::Install.run(config, latest, raise_on_failure: true, reporter: Reporter::Null.new)
        File.read(tmpdir / "node_modules/trusted/index.js").should eq("2.0.0")
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end

  it "ignores excluded packages" do
    It.with_registry do |registry|
      registry.add("trusted", "1.0.0", It.pkg("trusted", "1.0.0"), {"index.js" => "1.0.0"}, signature: true)

      tmpdir = Path.new(Dir.tempdir, "zap-it-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(tmpdir)
        File.write(tmpdir / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"trusted":"^1.0.0"},"zap":{"trust_policy":"no-downgrade","trust_policy_exclude":["trusted"]}}))
        File.write(tmpdir / ".npmrc", "registry=#{registry.base_url}/\n")
        config = Core::Config.new.copy_with(prefix: tmpdir.to_s, store_path: (tmpdir / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)

        registry.add("trusted", "2.0.0", It.pkg("trusted", "2.0.0"), {"index.js" => "2.0.0"})
        latest = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true, update_all: true, update_latest: true)
        Commands::Install.run(config, latest, raise_on_failure: true, reporter: Reporter::Null.new)
        File.read(tmpdir / "node_modules/trusted/index.js").should eq("2.0.0")
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end

  it "does nothing without the policy" do
    It.with_registry do |registry|
      registry.add("trusted", "1.0.0", It.pkg("trusted", "1.0.0"), {"index.js" => "1.0.0"}, signature: true)

      tmpdir = Path.new(Dir.tempdir, "zap-it-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(tmpdir)
        File.write(tmpdir / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"trusted":"^1.0.0"}}))
        File.write(tmpdir / ".npmrc", "registry=#{registry.base_url}/\n")
        config = Core::Config.new.copy_with(prefix: tmpdir.to_s, store_path: (tmpdir / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)

        registry.add("trusted", "2.0.0", It.pkg("trusted", "2.0.0"), {"index.js" => "2.0.0"})
        latest = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true, update_all: true, update_latest: true)
        Commands::Install.run(config, latest, raise_on_failure: true, reporter: Reporter::Null.new)
        File.read(tmpdir / "node_modules/trusted/index.js").should eq("2.0.0")
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end
end

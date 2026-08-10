require "./spec_helper"

# Production installs: dev dependencies are omitted from node_modules but
# the lockfile keeps the full dependency graph (npm parity), and a frozen
# production install against an unchanged lockfile succeeds.
describe "production installs", tags: "integration" do
  it "keeps the lockfile complete when omitting dev dependencies" do
    It.with_registry do |registry|
      registry.add("devonly", "1.0.0", It.pkg("devonly", "1.0.0"), {"index.js" => "d"})

      tmpdir = Path.new(Dir.tempdir, "zap-it-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(tmpdir)
        File.write(tmpdir / "package.json", %({"name":"app","version":"1.0.0","dependencies":{},"devDependencies":{"devonly":"1.0.0"}}))
        File.write(tmpdir / ".npmrc", "registry=#{registry.base_url}/\n")
        config = Core::Config.new.copy_with(prefix: tmpdir.to_s, store_path: (tmpdir / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)
        full_lockfile = File.read(tmpdir / "zap.lock")
        full_lockfile.should contain("devonly@1.0.0")

        # Production install: dev deps omitted from node_modules, lockfile untouched
        prod = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true, omit: [Commands::Install::Config::Omit::Dev])
        Commands::Install.run(config, prod, raise_on_failure: true, reporter: Reporter::Null.new)

        File.exists?(tmpdir / "node_modules/devonly").should be_false
        File.read(tmpdir / "zap.lock").should eq(full_lockfile)
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end

  it "succeeds a frozen production install against an unchanged lockfile" do
    It.with_registry do |registry|
      registry.add("devonly", "1.0.0", It.pkg("devonly", "1.0.0"), {"index.js" => "d"})

      tmpdir = Path.new(Dir.tempdir, "zap-it-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(tmpdir)
        File.write(tmpdir / "package.json", %({"name":"app","version":"1.0.0","dependencies":{},"devDependencies":{"devonly":"1.0.0"}}))
        File.write(tmpdir / ".npmrc", "registry=#{registry.base_url}/\n")
        config = Core::Config.new.copy_with(prefix: tmpdir.to_s, store_path: (tmpdir / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)

        frozen_prod = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: true, save: false, omit: [Commands::Install::Config::Omit::Dev])
        Commands::Install.run(config, frozen_prod, raise_on_failure: true, reporter: Reporter::Null.new)
        File.exists?(tmpdir / "node_modules/devonly").should be_false
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end

  it "omits dev dependencies with the isolated strategy" do
    It.with_registry do |registry|
      registry.add("devonly", "1.0.0", It.pkg("devonly", "1.0.0"), {"index.js" => "d"})

      tmpdir = Path.new(Dir.tempdir, "zap-it-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(tmpdir)
        File.write(tmpdir / "package.json", %({"name":"app","version":"1.0.0","dependencies":{},"devDependencies":{"devonly":"1.0.0"}}))
        File.write(tmpdir / ".npmrc", "registry=#{registry.base_url}/\n")
        config = Core::Config.new.copy_with(prefix: tmpdir.to_s, store_path: (tmpdir / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: false, strategy: Data::Package::InstallStrategy::Isolated, omit: [Commands::Install::Config::Omit::Dev])
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)

        File.exists?(tmpdir / "node_modules/devonly").should be_false
        File.exists?(tmpdir / "node_modules/.store").should be_true
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end
end

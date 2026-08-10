require "../../../store/store"
require "../../../store/config"
require "./spec_helper"

# Global installs and store maintenance commands.
describe "global installs and store", tags: "integration" do
  it "installs packages into the global prefix" do
    It.with_registry do |registry|
      registry.add("global-pkg", "1.0.0", It.pkg("global-pkg", "1.0.0"), {"index.js" => "g"})

      tmpdir = Path.new(Dir.tempdir, "zap-it-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(tmpdir)
        File.write(tmpdir / "package.json", %({"name":"app","version":"1.0.0"}))
        File.write(tmpdir / ".npmrc", "registry=#{registry.base_url}/\n")
        config = Core::Config.new.copy_with(prefix: tmpdir.to_s, store_path: (tmpdir / "store").to_s, silent: true, global: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true, added_packages: ["global-pkg"])
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)

        File.read(tmpdir / "lib/node_modules/global-pkg/index.js").should eq("g")
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end

  it "clears store packages and the whole store" do
    It.with_registry do |registry|
      registry.add("stored", "1.0.0", It.pkg("stored", "1.0.0"), {"index.js" => "s"})

      tmpdir = Path.new(Dir.tempdir, "zap-it-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(tmpdir)
        File.write(tmpdir / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"stored":"1.0.0"}}))
        File.write(tmpdir / ".npmrc", "registry=#{registry.base_url}/\n")
        config = Core::Config.new.copy_with(prefix: tmpdir.to_s, store_path: (tmpdir / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: false)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)

        store = tmpdir / "store"
        Dir.exists?(store / "packages").should be_true

        Commands::Store.run(config, Commands::Store::Config.new(action: Commands::Store::Config::StoreAction::ClearPackages))
        Dir.exists?(store / "packages").should be_false

        Commands::Store.run(config, Commands::Store::Config.new(action: Commands::Store::Config::StoreAction::Clear))
        Dir.exists?(store).should be_false
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end
end

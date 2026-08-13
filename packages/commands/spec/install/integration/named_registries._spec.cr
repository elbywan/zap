require "./spec_helper"

# pnpm's namedRegistries: a dependency can pin its source registry with an
# alias prefix in the specifier, and the lockfile records the registry so a
# package cannot be quietly substituted by another registry publishing the
# same name and version.
describe "named registries", tags: "integration" do
  it "resolves a named registry dependency from the aliased registry" do
    default = Zap::Integration::Registry.new
    named = Zap::Integration::Registry.new
    tmpdir = Path.new(Dir.tempdir, "zap-it-#{Random::Secure.hex(4)}")
    begin
      named.add("corp-lib", "1.0.0", It.pkg("corp-lib", "1.0.0"), {"index.js" => "from-named"})

      Dir.mkdir_p(tmpdir)
      File.write(tmpdir / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"corp-lib":"work:^1.0.0"},"zap":{"named_registries":{"work":"#{named.base_url}"}}}))
      File.write(tmpdir / ".npmrc", "registry=#{default.base_url}/\n")
      config = Core::Config.new.copy_with(prefix: tmpdir.to_s, store_path: (tmpdir / "store").to_s, silent: true)
      ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true)
      Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)

      File.read(tmpdir / "node_modules/corp-lib/index.js").should eq("from-named")
      # The lockfile records the registry-qualified key
      File.read(tmpdir / "zap.lock").should contain("corp-lib@work:1.0.0")
    ensure
      default.stop
      named.stop
      FileUtils.rm_rf(tmpdir)
    end
  end

  it "does not substitute a same-name package from the default registry" do
    default = Zap::Integration::Registry.new
    named = Zap::Integration::Registry.new
    tmpdir = Path.new(Dir.tempdir, "zap-it-#{Random::Secure.hex(4)}")
    begin
      default.add("corp-lib", "1.0.0", It.pkg("corp-lib", "1.0.0"), {"index.js" => "from-default"})
      named.add("corp-lib", "1.0.0", It.pkg("corp-lib", "1.0.0"), {"index.js" => "from-named"})

      Dir.mkdir_p(tmpdir)
      File.write(tmpdir / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"corp-lib":"work:^1.0.0"},"zap":{"named_registries":{"work":"#{named.base_url}"}}}))
      File.write(tmpdir / ".npmrc", "registry=#{default.base_url}/\n")
      config = Core::Config.new.copy_with(prefix: tmpdir.to_s, store_path: (tmpdir / "store").to_s, silent: true)
      ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true)
      Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)

      # The named registry wins, not the default registry's same-name package
      File.read(tmpdir / "node_modules/corp-lib/index.js").should eq("from-named")
    ensure
      default.stop
      named.stop
      FileUtils.rm_rf(tmpdir)
    end
  end
end

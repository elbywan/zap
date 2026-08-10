require "./spec_helper"

# Scoped registries: @scope:registry=.npmrc entries route scoped packages
# to a dedicated registry, mirroring npm/pnpm behavior.
describe "scoped registries", tags: "integration" do
  it "routes scoped packages to the scoped registry" do
    It.with_registry do |registry|
      registry.add("@myscope/pkg", "1.0.0", It.pkg("myscope/pkg", "1.0.0"), {"index.js" => "scoped"})

      tmpdir = Path.new(Dir.tempdir, "zap-it-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(tmpdir)
        File.write(tmpdir / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"@myscope/pkg":"1.0.0"}}))
        File.write(tmpdir / ".npmrc", "@myscope:registry=#{registry.base_url}/\n")
        config = Core::Config.new.copy_with(prefix: tmpdir.to_s, store_path: (tmpdir / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)

        File.read(tmpdir / "node_modules/@myscope/pkg/index.js").should eq("scoped")
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end

  it "mixes a scoped registry with the default registry" do
    It.with_registry do |registry|
      registry.add("plain", "1.0.0", It.pkg("plain", "1.0.0"), {"index.js" => "plain"})
      scoped = It::Registry.new
      begin
        scoped.add("@myscope/pkg", "1.0.0", It.pkg("myscope/pkg", "1.0.0"), {"index.js" => "scoped"})

        tmpdir = Path.new(Dir.tempdir, "zap-it-#{Random::Secure.hex(4)}")
        begin
          Dir.mkdir_p(tmpdir)
          File.write(tmpdir / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"plain":"1.0.0","@myscope/pkg":"1.0.0"}}))
          File.write(tmpdir / ".npmrc", "registry=#{registry.base_url}/\n@myscope:registry=#{scoped.base_url}/\n")
          config = Core::Config.new.copy_with(prefix: tmpdir.to_s, store_path: (tmpdir / "store").to_s, silent: true)
          ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true)
          Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)

          File.read(tmpdir / "node_modules/plain/index.js").should eq("plain")
          File.read(tmpdir / "node_modules/@myscope/pkg/index.js").should eq("scoped")
        ensure
          FileUtils.rm_rf(tmpdir)
        end
      ensure
        scoped.stop
      end
    end
  end
end

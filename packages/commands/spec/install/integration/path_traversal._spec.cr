require "./spec_helper"

describe "path safety", tags: "integration" do
  [
    {Data::Package::InstallStrategy::Classic, "classic"},
    {Data::Package::InstallStrategy::Isolated, "isolated"},
    {Data::Package::InstallStrategy::Pnp, "pnp"},
  ].each do |(strategy, name)|
    it "does not let package names escape node_modules (#{name})" do
      tmpdir = Path.new(Dir.tempdir, "zap-it-#{Random::Secure.hex(4)}")
      project = tmpdir / "project"
      package = tmpdir / "pkg"
      begin
        Dir.mkdir_p(project)
        Dir.mkdir_p(package)
        File.write(package / "package.json", %({"name":"../ESCAPED","version":"1.0.0"}))
        File.write(project / "package.json", %({"name":"path-safety","version":"1.0.0","dependencies":{"../ESCAPED":"file:../pkg"}}))

        config = Core::Config.new.copy_with(
          prefix: project.to_s,
          store_path: (tmpdir / "store").to_s,
          silent: true,
        )
        install_config = Commands::Install::Config.new.copy_with(
          workers: 1, frozen_lockfile: false, save: false, strategy: strategy
        )

        begin
          Commands::Install.run(config, install_config, raise_on_failure: true, reporter: Reporter::Null.new)
        rescue ex
          # The linkers that materialize the package path reject it; the PnP
          # file: shortcut only records a manifest entry and has no path to
          # escape.
          ex.message.not_nil!.should contain("escapes")
        end
        File.exists?(project / "ESCAPED").should be_false
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end
end

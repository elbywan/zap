require "./spec_helper"

# The project lock lives in the store, so a read-only project root must not
# prevent an otherwise no-op install.
{% unless flag?(:windows) %}
  describe "read-only projects", tags: "integration" do
    it "still installs when the project root is read-only" do
      It.with_registry do |registry|
        registry.add("ro-dep", "1.0.0", It.pkg("ro-dep", "1.0.0"), {"index.js" => "x"})
        It.install_project(registry, %({"name":"app","version":"1.0.0","dependencies":{"ro-dep":"1.0.0"}})) do |project|
          config = Core::Config.new.copy_with(prefix: project.to_s, store_path: (project / "store").to_s, silent: true)
          install_config = Commands::Install::Config.new.copy_with(
            workers: 1, frozen_lockfile: false, save: false
          )

          File.chmod(project, 0o555)
          begin
            Commands::Install.run(config, install_config, raise_on_failure: true, reporter: Reporter::Null.new)
          ensure
            File.chmod(project, 0o755)
          end
        end
      end
    end

    it "falls back to the home lock when the store is read-only" do
      It.with_registry do |registry|
        registry.add("ro-store-dep", "1.0.0", It.pkg("ro-store-dep", "1.0.0"), {"index.js" => "x"})
        It.install_project(registry, %({"name":"app","version":"1.0.0","dependencies":{"ro-store-dep":"1.0.0"}})) do |project|
          config = Core::Config.new.copy_with(prefix: project.to_s, store_path: (project / "store").to_s, silent: true)
          install_config = Commands::Install::Config.new.copy_with(
            workers: 1, frozen_lockfile: false, save: false
          )

          # Materialize the lockfile and the up-to-date fingerprint first.
          Commands::Install.run(
            config,
            install_config.copy_with(save: true),
            raise_on_failure: true,
            reporter: Reporter::Null.new
          )
          Dir.glob(project / "store" / "locks" / "project-*.lock") { |path| File.delete?(path) }

          home = Path.new(Dir.tempdir, "zap-home-#{Random::Secure.hex(4)}")
          Dir.mkdir_p(home)
          previous_home = ENV["HOME"]?
          begin
            ENV["HOME"] = home.to_s
            File.chmod(project / "store" / "locks", 0o555)
            begin
              Commands::Install.run(config, install_config, raise_on_failure: true, reporter: Reporter::Null.new)
            ensure
              File.chmod(project / "store" / "locks", 0o755)
            end
            Dir.children(home / ".zap" / "locks").size.should eq(1)
          ensure
            if previous_home
              ENV["HOME"] = previous_home
            else
              ENV.delete("HOME")
            end
            FileUtils.rm_rf(home)
          end
        end
      end
    end
  end
{% end %}

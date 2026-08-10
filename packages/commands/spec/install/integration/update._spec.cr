require "./spec_helper"

# --update semantics: the lockfile is honored on plain reinstalls; the
# update flags re-resolve from the registry and pick the newest version
# within the declared range.
describe "update semantics", tags: "integration" do
  it "honors the lockfile on reinstall and bumps with --update" do
    It.with_registry do |registry|
      registry.add("pinned", "1.0.0", It.pkg("pinned", "1.0.0"), {"index.js" => "1.0.0"})

      tmpdir = Path.new(Dir.tempdir, "zap-it-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(tmpdir)
        File.write(tmpdir / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"pinned":"^1.0.0"}}))
        File.write(tmpdir / ".npmrc", "registry=#{registry.base_url}/\n")
        config = Core::Config.new.copy_with(prefix: tmpdir.to_s, store_path: (tmpdir / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)
        File.read(tmpdir / "node_modules/pinned/index.js").should eq("1.0.0")

        # A newer version is published within the declared range
        registry.add("pinned", "1.5.0", It.pkg("pinned", "1.5.0"), {"index.js" => "1.5.0"})

        # Plain reinstall keeps the pinned version
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)
        File.read(tmpdir / "node_modules/pinned/index.js").should eq("1.0.0")

        # --update re-resolves and picks the newest satisfying version
        update_ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true, update_all: true)
        Commands::Install.run(config, update_ic, raise_on_failure: true, reporter: Reporter::Null.new)
        File.read(tmpdir / "node_modules/pinned/index.js").should eq("1.5.0")
        File.read(tmpdir / "zap.lock").should contain("pinned@1.5.0")
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end

  it "updates only the named packages with --update <package>" do
    It.with_registry do |registry|
      registry.add("stay", "1.0.0", It.pkg("stay", "1.0.0"), {"index.js" => "1.0.0"})
      registry.add("bump", "1.0.0", It.pkg("bump", "1.0.0"), {"index.js" => "1.0.0"})

      tmpdir = Path.new(Dir.tempdir, "zap-it-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(tmpdir)
        File.write(tmpdir / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"stay":"^1.0.0","bump":"^1.0.0"}}))
        File.write(tmpdir / ".npmrc", "registry=#{registry.base_url}/\n")
        config = Core::Config.new.copy_with(prefix: tmpdir.to_s, store_path: (tmpdir / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)

        registry.add("stay", "1.5.0", It.pkg("stay", "1.5.0"), {"index.js" => "1.5.0"})
        registry.add("bump", "1.5.0", It.pkg("bump", "1.5.0"), {"index.js" => "1.5.0"})

        targeted = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true, updated_packages: ["bump"])
        Commands::Install.run(config, targeted, raise_on_failure: true, reporter: Reporter::Null.new)

        File.read(tmpdir / "node_modules/bump/index.js").should eq("1.5.0")
        File.read(tmpdir / "node_modules/stay/index.js").should eq("1.0.0")
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end
end

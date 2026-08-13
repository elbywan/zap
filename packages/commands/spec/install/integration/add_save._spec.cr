require "./spec_helper"

# `zap add` behaviors: saving a new dependency into package.json with the
# default caret range, exact versions, --save-dev, and explicit versions.
describe "add and save", tags: "integration" do
  it "adds a dependency with a caret range by default" do
    It.with_registry do |registry|
      registry.add("fresh", "1.2.3", It.pkg("fresh", "1.2.3"), {"index.js" => "f"})

      tmpdir = Path.new(Dir.tempdir, "zap-it-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(tmpdir)
        File.write(tmpdir / "package.json", %({"name":"app","version":"1.0.0"}))
        File.write(tmpdir / ".npmrc", "registry=#{registry.base_url}/\n")
        config = Core::Config.new.copy_with(prefix: tmpdir.to_s, store_path: (tmpdir / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true, added_packages: ["fresh"])
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)

        pkg = JSON.parse(File.read(tmpdir / "package.json"))
        pkg["dependencies"]["fresh"].as_s.should eq("^1.2.3")
        File.read(tmpdir / "node_modules/fresh/index.js").should eq("f")
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end

  it "saves an exact version with --save-exact" do
    It.with_registry do |registry|
      registry.add("fresh", "1.2.3", It.pkg("fresh", "1.2.3"), {"index.js" => "f"})

      tmpdir = Path.new(Dir.tempdir, "zap-it-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(tmpdir)
        File.write(tmpdir / "package.json", %({"name":"app","version":"1.0.0"}))
        File.write(tmpdir / ".npmrc", "registry=#{registry.base_url}/\n")
        config = Core::Config.new.copy_with(prefix: tmpdir.to_s, store_path: (tmpdir / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true, save_exact: true, added_packages: ["fresh"])
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)

        pkg = JSON.parse(File.read(tmpdir / "package.json"))
        pkg["dependencies"]["fresh"].as_s.should eq("1.2.3")
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end

  it "saves a dev dependency with --save-dev" do
    It.with_registry do |registry|
      registry.add("dev-only", "1.0.0", It.pkg("dev-only", "1.0.0"), {"index.js" => "d"})

      tmpdir = Path.new(Dir.tempdir, "zap-it-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(tmpdir)
        File.write(tmpdir / "package.json", %({"name":"app","version":"1.0.0"}))
        File.write(tmpdir / ".npmrc", "registry=#{registry.base_url}/\n")
        config = Core::Config.new.copy_with(prefix: tmpdir.to_s, store_path: (tmpdir / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true, save_dev: true, added_packages: ["dev-only"])
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)

        pkg = JSON.parse(File.read(tmpdir / "package.json"))
        pkg["dependencies"]?.should be_nil
        pkg["devDependencies"]["dev-only"].as_s.should eq("^1.0.0")
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end

  it "keeps an explicitly requested version without a caret" do
    It.with_registry do |registry|
      registry.add("pinned", "1.0.0", It.pkg("pinned", "1.0.0"), {"index.js" => "p"})
      registry.add("pinned", "1.5.0", It.pkg("pinned", "1.5.0"), {"index.js" => "1.5.0"})

      tmpdir = Path.new(Dir.tempdir, "zap-it-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(tmpdir)
        File.write(tmpdir / "package.json", %({"name":"app","version":"1.0.0"}))
        File.write(tmpdir / ".npmrc", "registry=#{registry.base_url}/\n")
        config = Core::Config.new.copy_with(prefix: tmpdir.to_s, store_path: (tmpdir / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true, added_packages: ["pinned@1.0.0"])
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)

        pkg = JSON.parse(File.read(tmpdir / "package.json"))
        pkg["dependencies"]["pinned"].as_s.should eq("1.0.0")
        # The resolved install is the exact version, not the newest in range
        File.read(tmpdir / "node_modules/pinned/index.js").should eq("p")
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end

  it "uses the configured tilde prefix instead of the caret" do
    It.with_registry do |registry|
      registry.add("fresh", "1.2.3", It.pkg("fresh", "1.2.3"), {"index.js" => "f"})

      tmpdir = Path.new(Dir.tempdir, "zap-it-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(tmpdir)
        File.write(tmpdir / "package.json", %({"name":"app","version":"1.0.0","zap":{"default_semver_range_prefix":"~"}}))
        File.write(tmpdir / ".npmrc", "registry=#{registry.base_url}/\n")
        config = Core::Config.new.copy_with(prefix: tmpdir.to_s, store_path: (tmpdir / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true, added_packages: ["fresh"])
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)

        pkg = JSON.parse(File.read(tmpdir / "package.json"))
        pkg["dependencies"]["fresh"].as_s.should eq("~1.2.3")
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end

  it "saves exact versions with an empty prefix" do
    It.with_registry do |registry|
      registry.add("fresh", "1.2.3", It.pkg("fresh", "1.2.3"), {"index.js" => "f"})

      tmpdir = Path.new(Dir.tempdir, "zap-it-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(tmpdir)
        File.write(tmpdir / "package.json", %({"name":"app","version":"1.0.0","zap":{"default_semver_range_prefix":""}}))
        File.write(tmpdir / ".npmrc", "registry=#{registry.base_url}/\n")
        config = Core::Config.new.copy_with(prefix: tmpdir.to_s, store_path: (tmpdir / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true, added_packages: ["fresh"])
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)

        pkg = JSON.parse(File.read(tmpdir / "package.json"))
        pkg["dependencies"]["fresh"].as_s.should eq("1.2.3")
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end
end

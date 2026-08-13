require "../../../approve-builds/approve-builds"
require "./spec_helper"

# The approve-builds review: which packages have pending build scripts, and
# how the decisions are persisted into the zap section of package.json.
# The interactive TUI selection itself is not exercised (it needs a TTY).
describe "approve-builds", tags: "integration" do
  it "lists the packages with pending build scripts" do
    It.with_registry do |registry|
      registry.add("scripted", "1.0.0", It.pkg("scripted", "1.0.0",
        scripts: {"install" => "node -e \"1\""}),
        {"index.js" => "s"})
      registry.add("plain", "1.0.0", It.pkg("plain", "1.0.0"), {"index.js" => "p"})

      tmpdir = Path.new(Dir.tempdir, "zap-it-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(tmpdir)
        File.write(tmpdir / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"scripted":"1.0.0","plain":"1.0.0"}}))
        File.write(tmpdir / ".npmrc", "registry=#{registry.base_url}/\n")
        config = Core::Config.new.copy_with(prefix: tmpdir.to_s, store_path: (tmpdir / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)

        lockfile = Data::Lockfile.new(tmpdir)
        main = Data::Package.init(tmpdir / "package.json", append_filename: false)
        store = ::Store.new((tmpdir / "store").to_s)
        pending = Commands::ApproveBuilds.pending_packages(lockfile, main, store)
        pending.map(&.name).should eq(["scripted"])
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end

  it "excludes allowlisted and ignored packages from the pending list" do
    It.with_registry do |registry|
      registry.add("scripted", "1.0.0", It.pkg("scripted", "1.0.0",
        scripts: {"install" => "node -e \"1\""}),
        {"index.js" => "s"})
      registry.add("other", "1.0.0", It.pkg("other", "1.0.0",
        scripts: {"postinstall" => "node -e \"1\""}),
        {"index.js" => "o"})

      tmpdir = Path.new(Dir.tempdir, "zap-it-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(tmpdir)
        File.write(tmpdir / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"scripted":"1.0.0","other":"1.0.0"},"zap":{"only_built_dependencies":["scripted"],"ignored_built_dependencies":["other"]}}))
        File.write(tmpdir / ".npmrc", "registry=#{registry.base_url}/\n")
        config = Core::Config.new.copy_with(prefix: tmpdir.to_s, store_path: (tmpdir / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)

        lockfile = Data::Lockfile.new(tmpdir)
        main = Data::Package.init(tmpdir / "package.json", append_filename: false)
        store = ::Store.new((tmpdir / "store").to_s)
        Commands::ApproveBuilds.pending_packages(lockfile, main, store).should be_empty
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end

  it "lists packages with an implicit node-gyp build" do
    It.with_registry do |registry|
      registry.add("native", "1.0.0", It.pkg("native", "1.0.0"), {"index.js" => "n", "binding.gyp" => ""})

      tmpdir = Path.new(Dir.tempdir, "zap-it-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(tmpdir)
        File.write(tmpdir / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"native":"1.0.0"}}))
        File.write(tmpdir / ".npmrc", "registry=#{registry.base_url}/\n")
        config = Core::Config.new.copy_with(prefix: tmpdir.to_s, store_path: (tmpdir / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)

        lockfile = Data::Lockfile.new(tmpdir)
        main = Data::Package.init(tmpdir / "package.json", append_filename: false)
        store = ::Store.new((tmpdir / "store").to_s)
        pending = Commands::ApproveBuilds.pending_packages(lockfile, main, store)
        pending.map(&.name).should eq(["native"])
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end

  it "persists the decisions into the zap section of package.json" do
    tmpdir = Path.new(Dir.tempdir, "zap-ab-#{Random::Secure.hex(4)}")
    begin
      Dir.mkdir_p(tmpdir)
      File.write(tmpdir / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"a":"1.0.0"}}))
      Commands::ApproveBuilds.write_approvals(tmpdir.to_s, ["a"], ["b"])
      pkg = JSON.parse(File.read(tmpdir / "package.json"))
      pkg["zap"]["only_built_dependencies"].as_a.map(&.as_s).should eq(["a"])
      pkg["zap"]["ignored_built_dependencies"].as_a.map(&.as_s).should eq(["b"])
      # The rest of the file is preserved
      pkg["dependencies"]["a"].as_s.should eq("1.0.0")
    ensure
      FileUtils.rm_rf(tmpdir)
    end
  end

  it "merges with the existing allowlist and ignore list" do
    tmpdir = Path.new(Dir.tempdir, "zap-ab-#{Random::Secure.hex(4)}")
    begin
      Dir.mkdir_p(tmpdir)
      File.write(tmpdir / "package.json", %({"name":"app","version":"1.0.0","zap":{"only_built_dependencies":["a"],"ignored_built_dependencies":["b"]}}))
      Commands::ApproveBuilds.write_approvals(tmpdir.to_s, ["a", "c"], ["b"])
      pkg = JSON.parse(File.read(tmpdir / "package.json"))
      pkg["zap"]["only_built_dependencies"].as_a.map(&.as_s).should eq(["a", "c"])
      pkg["zap"]["ignored_built_dependencies"].as_a.map(&.as_s).should eq(["b"])
    ensure
      FileUtils.rm_rf(tmpdir)
    end
  end
end

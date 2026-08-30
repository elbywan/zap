require "./spec_helper"

# The up-to-date fast path (issue #48): when nothing relevant changed since
# the last completed install, the install pass is skipped entirely.
describe "fast path", tags: "integration" do
  it "skips the install pass when nothing changed" do
    It.with_registry do |registry|
      registry.add("fresh", "1.2.3", It.pkg("fresh", "1.2.3"), {"index.js" => "f"})

      tmpdir = Path.new(Dir.tempdir, "zap-it-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(tmpdir)
        File.write(tmpdir / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"fresh":"1.2.3"}}))
        File.write(tmpdir / ".npmrc", "registry=#{registry.base_url}/\n")
        config = Core::Config.new.copy_with(prefix: tmpdir.to_s, store_path: (tmpdir / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, check_resolutions: false)

        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)

        lockfile_mtime = File.info(tmpdir / "zap.lock").modification_time
        file_mtime = File.info(tmpdir / "node_modules/fresh/index.js").modification_time
        state_mtime = File.info(tmpdir / "node_modules/.zap-state").modification_time
        fingerprint = File.read(tmpdir / "node_modules/.zap-fingerprint")

        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)

        File.info(tmpdir / "zap.lock").modification_time.should eq(lockfile_mtime)
        File.info(tmpdir / "node_modules/fresh/index.js").modification_time.should eq(file_mtime)
        File.info(tmpdir / "node_modules/.zap-state").modification_time.should eq(state_mtime)
        File.read(tmpdir / "node_modules/.zap-fingerprint").should eq(fingerprint)
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end

  it "re-runs the install pass when package.json changed" do
    It.with_registry do |registry|
      registry.add("fresh", "1.2.3", It.pkg("fresh", "1.2.3"), {"index.js" => "f"})

      tmpdir = Path.new(Dir.tempdir, "zap-it-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(tmpdir)
        File.write(tmpdir / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"fresh":"1.2.3"}}))
        File.write(tmpdir / ".npmrc", "registry=#{registry.base_url}/\n")
        config = Core::Config.new.copy_with(prefix: tmpdir.to_s, store_path: (tmpdir / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, check_resolutions: false)

        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)
        lockfile_mtime = File.info(tmpdir / "zap.lock").modification_time
        sleep 10.milliseconds

        File.write(tmpdir / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"fresh":"^1.0.0"}}))
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)

        File.info(tmpdir / "zap.lock").modification_time.should_not eq(lockfile_mtime)
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end

  it "re-runs the install pass when a workspace member changed" do
    It.with_registry do |registry|
      ws_root = Path.new(Dir.tempdir, "zap-ws-test-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(ws_root / "packages/a")
        Dir.mkdir_p(ws_root / "packages/b")
        File.write(ws_root / "package.json", %({"name":"ws-root","version":"1.0.0","workspaces":["packages/*"]}))
        File.write(ws_root / ".npmrc", "registry=#{registry.base_url}/\n")
        File.write(ws_root / "packages/a/package.json", %({"name":"ws-a","version":"1.0.0","main":"index.js"}))
        File.write(ws_root / "packages/a/index.js", "ws-a")
        File.write(ws_root / "packages/b/package.json", %({"name":"ws-b","version":"1.0.0"}))
        File.write(ws_root / "packages/b/index.js", "ws-b")

        config = Core::Config.new.copy_with(prefix: ws_root.to_s, store_path: (ws_root / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, check_resolutions: false)

        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)
        lockfile_mtime = File.info(ws_root / "zap.lock").modification_time
        sleep 10.milliseconds

        File.write(ws_root / "packages/b/package.json", %({"name":"ws-b","version":"2.0.0"}))
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)

        File.info(ws_root / "zap.lock").modification_time.should_not eq(lockfile_mtime)
      ensure
        FileUtils.rm_rf(ws_root)
      end
    end
  end

  it "re-runs the install pass when the lockfile was edited" do
    It.with_registry do |registry|
      registry.add("fresh", "1.2.3", It.pkg("fresh", "1.2.3"), {"index.js" => "f"})

      tmpdir = Path.new(Dir.tempdir, "zap-it-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(tmpdir)
        File.write(tmpdir / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"fresh":"1.2.3"}}))
        File.write(tmpdir / ".npmrc", "registry=#{registry.base_url}/\n")
        config = Core::Config.new.copy_with(prefix: tmpdir.to_s, store_path: (tmpdir / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, check_resolutions: false)

        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)

        lockfile = tmpdir / "zap.lock"
        lockfile_mtime = File.info(lockfile).modification_time
        # A manual edit (even a whitespace-only one) must invalidate the
        # fast path: the next install re-resolves and rewrites the lockfile
        # instead of silently keeping the old tree.
        File.write(lockfile, File.read(lockfile) + "\n")

        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)

        File.info(lockfile).modification_time.should_not eq(lockfile_mtime)
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end

  it "re-runs the install pass when the lockfile is missing" do
    It.with_registry do |registry|
      registry.add("fresh", "1.2.3", It.pkg("fresh", "1.2.3"), {"index.js" => "f"})

      tmpdir = Path.new(Dir.tempdir, "zap-it-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(tmpdir)
        File.write(tmpdir / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"fresh":"1.2.3"}}))
        File.write(tmpdir / ".npmrc", "registry=#{registry.base_url}/\n")
        config = Core::Config.new.copy_with(prefix: tmpdir.to_s, store_path: (tmpdir / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, check_resolutions: false)

        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)
        File.delete(tmpdir / "zap.lock")

        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)

        File.exists?(tmpdir / "zap.lock").should be_true
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end
end

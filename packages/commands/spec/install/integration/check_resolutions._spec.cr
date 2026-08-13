require "./spec_helper"

# yarn's --check-resolutions (YN0078): the lockfile resolutions must satisfy
# the declared dependency ranges. A tampered lockfile (a resolution rewritten
# to a version outside the declared range) fails the install.
describe "check resolutions", tags: "integration" do
  it "passes when the lockfile resolutions match the declared ranges" do
    It.with_registry do |registry|
      registry.add("child", "1.2.0", It.pkg("child", "1.2.0"), {"index.js" => "1.2.0"})
      registry.add("parent", "1.0.0", It.pkg("parent", "1.0.0", dependencies: {"child" => "^1.0.0"}), {"index.js" => "p"})

      ic = Commands::Install::Config.new.copy_with(check_resolutions: true)
      It.install_project(registry, %({"name":"app","version":"1.0.0","dependencies":{"parent":"1.0.0"}}), install_config: ic) do |project|
        File.read(project / "node_modules/child/index.js").should eq("1.2.0")
      end
    end
  end

  it "raises when a direct resolution was tampered in place" do
    It.with_registry do |registry|
      registry.add("a", "1.0.0", It.pkg("a", "1.0.0"), {"index.js" => "a"})

      tmpdir = Path.new(Dir.tempdir, "zap-it-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(tmpdir)
        File.write(tmpdir / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"a":"^1.0.0"}}))
        File.write(tmpdir / ".npmrc", "registry=#{registry.base_url}/\n")
        config = Core::Config.new.copy_with(prefix: tmpdir.to_s, store_path: (tmpdir / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)

        # An in-place edit of the direct entry's version, the key intact
        lock = File.read(tmpdir / "zap.lock")
        lock = lock.gsub("version: 1.0.0", "version: 1.0.1")
        File.write(tmpdir / "zap.lock", lock)

        expect_raises(Exception, /does not match its key/) do
          Commands::Install.run(config, ic.copy_with(check_resolutions: true), raise_on_failure: true, reporter: Reporter::Null.new)
        end
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end

  it "raises when a lockfile resolution was tampered with" do
    It.with_registry do |registry|
      registry.add("child", "1.2.0", It.pkg("child", "1.2.0"), {"index.js" => "1.2.0"})
      registry.add("child", "2.0.0", It.pkg("child", "2.0.0"), {"index.js" => "2.0.0"})
      registry.add("parent", "1.0.0", It.pkg("parent", "1.0.0", dependencies: {"child" => "^1.0.0"}), {"index.js" => "p"})

      tmpdir = Path.new(Dir.tempdir, "zap-it-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(tmpdir)
        File.write(tmpdir / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"parent":"1.0.0"}}))
        File.write(tmpdir / ".npmrc", "registry=#{registry.base_url}/\n")
        config = Core::Config.new.copy_with(prefix: tmpdir.to_s, store_path: (tmpdir / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)

        # A malicious edit rewrites the resolved version of child (keeping
        # the child@1.2.0 key), so the resolution no longer matches the
        # pinned dependency of its parent.
        lock = File.read(tmpdir / "zap.lock")
        lock = lock.gsub("version: 1.2.0", "version: 2.0.0")
        File.write(tmpdir / "zap.lock", lock)

        expect_raises(Exception, /resolves child to child@2\.0\.0.*declared range 1\.2\.0/) do
          Commands::Install.run(config, ic.copy_with(check_resolutions: true), raise_on_failure: true, reporter: Reporter::Null.new)
        end
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end
end

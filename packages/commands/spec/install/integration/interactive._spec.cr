require "./spec_helper"

module ItState
  # Mirrors the State construction in Install.run so the scan can be exercised
  # against a real registry without a TTY.
  def self.build(config : Core::Config, ic : Commands::Install::Config) : Commands::Install::State
    inferred = config.infer_context
    lockfile = Data::Lockfile.new(inferred.config.prefix)
    npmrc = Data::Npmrc.new(inferred.config.prefix)
    Commands::Install::State.new(
      config: inferred.config,
      install_config: ic,
      store: ::Store.new(inferred.config.store_path),
      main_package: inferred.main_package,
      lockfile: lockfile,
      context: inferred,
      npmrc: npmrc,
      registry_clients: Commands::Install::RegistryClients.new(inferred.config.store_path, npmrc, pool_max_size: 4),
      pipeline: Concurrency::Pipeline.new(workers: 1),
      reporter: Reporter::Null.new
    )
  end
end

# The interactive update scans the direct dependencies and reports the ones
# with a newer version available within their declared range.
describe "interactive update", tags: "integration" do
  it "scans the updateable direct dependencies" do
    It.with_registry do |registry|
      registry.add("pinned", "1.0.0", It.pkg("pinned", "1.0.0"), {"index.js" => "1.0.0"})
      registry.add("fresh", "1.0.0", It.pkg("fresh", "1.0.0"), {"index.js" => "1.0.0"})
      registry.add("stale", "1.0.0", It.pkg("stale", "1.0.0"), {"index.js" => "1.0.0"})

      tmpdir = Path.new(Dir.tempdir, "zap-it-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(tmpdir)
        File.write(tmpdir / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"pinned":"^1.0.0","fresh":"^1.0.0","stale":"^1.0.0"}}))
        File.write(tmpdir / ".npmrc", "registry=#{registry.base_url}/\n")
        config = Core::Config.new.copy_with(prefix: tmpdir.to_s, store_path: (tmpdir / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)

        # pinned: newer in-range version; fresh: newer but out of range;
        # stale: nothing newer.
        registry.add("pinned", "1.5.0", It.pkg("pinned", "1.5.0"), {"index.js" => "1.5.0"})
        registry.add("fresh", "2.0.0", It.pkg("fresh", "2.0.0"), {"index.js" => "2.0.0"})

        state = ItState.build(config, ic)
        updateable = Commands::Install::Interactive.scan(state)
        updateable.map(&.name).should eq(["pinned"])
        pinned = updateable.find { |u| u.name == "pinned" }.not_nil!
        pinned.current.should eq("1.0.0")
        pinned.target.should eq("1.5.0")
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end

  it "scans dev and optional dependencies too" do
    It.with_registry do |registry|
      registry.add("devpkg", "1.0.0", It.pkg("devpkg", "1.0.0"), {"index.js" => "1.0.0"})
      registry.add("optpkg", "1.0.0", It.pkg("optpkg", "1.0.0"), {"index.js" => "1.0.0"})

      tmpdir = Path.new(Dir.tempdir, "zap-it-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(tmpdir)
        File.write(tmpdir / "package.json", %({"name":"app","version":"1.0.0","devDependencies":{"devpkg":"^1.0.0"},"optionalDependencies":{"optpkg":"^1.0.0"}}))
        File.write(tmpdir / ".npmrc", "registry=#{registry.base_url}/\n")
        config = Core::Config.new.copy_with(prefix: tmpdir.to_s, store_path: (tmpdir / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)

        registry.add("devpkg", "1.2.0", It.pkg("devpkg", "1.2.0"), {"index.js" => "1.2.0"})
        registry.add("optpkg", "1.2.0", It.pkg("optpkg", "1.2.0"), {"index.js" => "1.2.0"})

        state = ItState.build(config, ic)
        updateable = Commands::Install::Interactive.scan(state)
        updateable.map(&.name).sort.should eq(["devpkg", "optpkg"])
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end
  it "only lists registry ranges, skipping aliases and git specifiers" do
    It.with_registry do |registry|
      registry.add("plain", "1.0.0", It.pkg("plain", "1.0.0"), {"index.js" => "1.0.0"})

      repo = Path.new(Dir.tempdir, "zap-git-#{Random::Secure.hex(4)}")
      tmpdir = Path.new(Dir.tempdir, "zap-it-#{Random::Secure.hex(4)}")
      begin
        It.make_git_repo(repo, %({"name":"gitted","version":"1.0.0","main":"index.js"}), {"index.js" => "v1"})
        Dir.mkdir_p(tmpdir)
        File.write(tmpdir / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"plain":"^1.0.0","my-alias":"npm:plain@1.0.0","gitted":"git+file://#{repo}#main"}}))
        File.write(tmpdir / ".npmrc", "registry=#{registry.base_url}/\n")
        config = Core::Config.new.copy_with(prefix: tmpdir.to_s, store_path: (tmpdir / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)

        registry.add("plain", "1.5.0", It.pkg("plain", "1.5.0"), {"index.js" => "1.5.0"})

        state = ItState.build(config, ic)
        updateable = Commands::Install::Interactive.scan(state)
        updateable.map(&.name).should eq(["plain"])
      ensure
        FileUtils.rm_rf(repo)
        FileUtils.rm_rf(tmpdir)
      end
    end
  end

  it "colors the version arrow by bump severity" do
    Commands::Install::Interactive.bump_color("1.0.0", "2.0.0").should eq(Tui::Ansi::RED)
    Commands::Install::Interactive.bump_color("1.0.0", "1.1.0").should eq(Tui::Ansi::YELLOW)
    Commands::Install::Interactive.bump_color("1.0.0", "1.0.1").should eq(Tui::Ansi::GREEN)
  end

  it "computes latest targets with --latest, matching the apply" do
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

        registry.add("pinned", "1.5.0", It.pkg("pinned", "1.5.0"), {"index.js" => "1.5.0"})
        registry.add("pinned", "2.0.0", It.pkg("pinned", "2.0.0"), {"index.js" => "2.0.0"})

        # Without --latest the target is in-range.
        in_range = Commands::Install::Interactive.scan(ItState.build(config, ic))
        in_range.first.target.should eq("1.5.0")

        # With --latest the target is the newest overall (out of range).
        latest = Commands::Install::Interactive.scan(ItState.build(config, ic.copy_with(update_latest: true)))
        latest.first.target.should eq("2.0.0")
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end

  it "scans the updateable dependencies of every workspace, deduplicated by name" do
    It.with_registry do |registry|
      registry.add("pinned", "1.0.0", It.pkg("pinned", "1.0.0"), {"index.js" => "1.0.0"})

      ws_root = Path.new(Dir.tempdir, "zap-it-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(ws_root / "packages/a")
        Dir.mkdir_p(ws_root / "packages/b")
        File.write(ws_root / "package.json", %({"name":"ws-root","version":"1.0.0","workspaces":["packages/*"]}))
        File.write(ws_root / ".npmrc", "registry=#{registry.base_url}/\n")
        File.write(ws_root / "packages/a/package.json", %({"name":"ws-a","version":"1.0.0","dependencies":{"pinned":"^1.0.0"}}))
        File.write(ws_root / "packages/a/index.js", "a")
        File.write(ws_root / "packages/b/package.json", %({"name":"ws-b","version":"1.0.0","dependencies":{"pinned":"^1.0.0"}}))
        File.write(ws_root / "packages/b/index.js", "b")

        config = Core::Config.new.copy_with(prefix: ws_root.to_s, store_path: (ws_root / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)

        registry.add("pinned", "1.5.0", It.pkg("pinned", "1.5.0"), {"index.js" => "1.5.0"})
        updateable = Commands::Install::Interactive.scan(ItState.build(config, ic))
        # One entry for the dep shared by both workspaces.
        updateable.map(&.name).should eq(["pinned"])
        updateable.first.current.should eq("1.0.0")
        updateable.first.target.should eq("1.5.0")
      ensure
        FileUtils.rm_rf(ws_root)
      end
    end
  end

  it "fails fast when the lockfile is missing" do
    It.with_registry do |registry|
      registry.add("pinned", "1.0.0", It.pkg("pinned", "1.0.0"), {"index.js" => "1.0.0"})

      tmpdir = Path.new(Dir.tempdir, "zap-it-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(tmpdir)
        File.write(tmpdir / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"pinned":"^1.0.0"}}))
        File.write(tmpdir / ".npmrc", "registry=#{registry.base_url}/\n")
        config = Core::Config.new.copy_with(prefix: tmpdir.to_s, store_path: (tmpdir / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true)
        # No install ran: there is no lockfile to read current versions from.
        state = ItState.build(config, ic)
        expect_raises(Exception, /lockfile/) do
          Commands::Install::Interactive.scan(state)
        end
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end

end

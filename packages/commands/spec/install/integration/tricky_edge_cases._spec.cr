require "./spec_helper"

# Tricky edge cases: npm overrides of dependencies by optionalDependencies,
# workspace version mismatches, frozen-install prerequisites, strategy
# switches, offline reinstalls, orphan pruning and peer version conflicts.
describe "tricky edge cases", tags: "integration" do
  it "lets optionalDependencies override a same-named dependency" do
    It.with_registry do |registry|
      registry.add("dep", "1.0.0", It.pkg("dep", "1.0.0"), {"index.js" => "1.0.0"})
      registry.add("dep", "2.0.0", It.pkg("dep", "2.0.0"), {"index.js" => "2.0.0"})
      registry.add("parent", "1.0.0", It.pkg("parent", "1.0.0",
        dependencies: {"dep" => "^1.0.0"}, optional_dependencies: {"dep" => "^2.0.0"}),
        {"index.js" => "parent"})

      It.install_project(registry, %({"name":"app","version":"1.0.0","dependencies":{"parent":"1.0.0"}})) do |project|
        # npm semantics: the optionalDependencies entry wins over dependencies
        File.read(project / "node_modules/dep/index.js").should eq("2.0.0")
      end
    end
  end

  it "falls back to the registry when the workspace version does not match the range" do
    It.with_registry do |registry|
      registry.add("ws-a", "2.0.0", It.pkg("ws-a", "2.0.0"), {"index.js" => "from-registry"})

      ws_root = Path.new(Dir.tempdir, "zap-ws-test-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(ws_root / "packages/a")
        File.write(ws_root / "package.json", %({"name":"ws-root","version":"1.0.0","workspaces":["packages/*"],"dependencies":{"ws-a":"^2.0.0"}}))
        File.write(ws_root / ".npmrc", "registry=#{registry.base_url}/\n")
        File.write(ws_root / "packages/a/package.json", %({"name":"ws-a","version":"1.0.0","main":"index.js"}))
        File.write(ws_root / "packages/a/index.js", "from-workspace")

        config = Core::Config.new.copy_with(prefix: ws_root.to_s, store_path: (ws_root / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: false)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)

        # ws-a@1.0.0 does not satisfy ^2.0.0, so the registry copy is installed
        File.read(ws_root / "node_modules/ws-a/index.js").should eq("from-registry")
      ensure
        FileUtils.rm_rf(ws_root)
      end
    end
  end

  it "raises when a workspace: protocol range does not match the workspace version" do
    It.with_registry do |registry|
      ws_root = Path.new(Dir.tempdir, "zap-ws-test-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(ws_root / "packages/a")
        File.write(ws_root / "package.json", %({"name":"ws-root","version":"1.0.0","workspaces":["packages/*"]}))
        File.write(ws_root / ".npmrc", "registry=#{registry.base_url}/\n")
        File.write(ws_root / "packages/a/package.json", %({"name":"ws-a","version":"1.0.0","main":"index.js"}))
        File.write(ws_root / "packages/a/index.js", "ws-a")
        File.write(ws_root / "packages/root-pkg.json", "")

        config = Core::Config.new.copy_with(prefix: ws_root.to_s, store_path: (ws_root / "store").to_s, silent: true)
        # Root depends on the workspace with an incompatible protocol range
        File.write(ws_root / "package.json", %({"name":"ws-root","version":"1.0.0","workspaces":["packages/*"],"dependencies":{"ws-a":"workspace:^2.0.0"}}))
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: false)
        expect_raises(Exception, /does not match version|not found/) do
          Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)
        end
      ensure
        FileUtils.rm_rf(ws_root)
      end
    end
  end

  it "raises a frozen install when no lockfile exists" do
    It.with_registry do |registry|
      registry.add("frozen", "1.0.0", It.pkg("frozen", "1.0.0"), {"index.js" => "f"})

      tmpdir = Path.new(Dir.tempdir, "zap-it-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(tmpdir)
        File.write(tmpdir / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"frozen":"1.0.0"}}))
        File.write(tmpdir / ".npmrc", "registry=#{registry.base_url}/\n")
        config = Core::Config.new.copy_with(prefix: tmpdir.to_s, store_path: (tmpdir / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: true, save: false)
        expect_raises(Exception, /frozen-lockfile/) do
          Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)
        end
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end

  it "re-lays-out node_modules when switching from classic to isolated" do
    It.with_registry do |registry|
      registry.add("b", "1.0.0", It.pkg("b", "1.0.0"), {"index.js" => "b"})
      registry.add("a", "1.0.0", It.pkg("a", "1.0.0", dependencies: {"b" => "1.0.0"}), {"index.js" => "a"})

      tmpdir = Path.new(Dir.tempdir, "zap-it-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(tmpdir)
        File.write(tmpdir / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"a":"1.0.0"}}))
        File.write(tmpdir / ".npmrc", "registry=#{registry.base_url}/\n")
        config = Core::Config.new.copy_with(prefix: tmpdir.to_s, store_path: (tmpdir / "store").to_s, silent: true)
        classic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true)
        Commands::Install.run(config, classic, raise_on_failure: true, reporter: Reporter::Null.new)
        File.directory?(tmpdir / "node_modules/a").should be_true

        isolated = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true, strategy: Data::Package::InstallStrategy::Isolated)
        Commands::Install.run(config, isolated, raise_on_failure: true, reporter: Reporter::Null.new)

        # The classic layout is replaced by symlinks into the virtual store
        File.symlink?(tmpdir / "node_modules/a").should be_true
        Dir.exists?(tmpdir / "node_modules/.store").should be_true
        File.read(tmpdir / "node_modules/a/index.js").should eq("a")
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end

  it "reinstalls from the lockfile and store without the registry" do
    It.with_registry do |registry|
      registry.add("off", "1.0.0", It.pkg("off", "1.0.0"), {"index.js" => "o"})

      tmpdir = Path.new(Dir.tempdir, "zap-it-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(tmpdir)
        File.write(tmpdir / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"off":"1.0.0"}}))
        File.write(tmpdir / ".npmrc", "registry=#{registry.base_url}/\n")
        config = Core::Config.new.copy_with(prefix: tmpdir.to_s, store_path: (tmpdir / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)

        registry.stop
        FileUtils.rm_rf(tmpdir / "node_modules")
        frozen = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: true, save: false)
        Commands::Install.run(config, frozen, raise_on_failure: true, reporter: Reporter::Null.new)
        File.read(tmpdir / "node_modules/off/index.js").should eq("o")
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end

  it "prunes a stale node_modules directory on reinstall" do
    It.with_registry do |registry|
      registry.add("kept", "1.0.0", It.pkg("kept", "1.0.0"), {"index.js" => "k"})

      tmpdir = Path.new(Dir.tempdir, "zap-it-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(tmpdir)
        File.write(tmpdir / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"kept":"1.0.0"}}))
        File.write(tmpdir / ".npmrc", "registry=#{registry.base_url}/\n")
        config = Core::Config.new.copy_with(prefix: tmpdir.to_s, store_path: (tmpdir / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)

        # A directory claiming to be a package that is not in the lockfile
        Dir.mkdir_p(tmpdir / "node_modules/stale")
        File.write(tmpdir / "node_modules/stale/.zap.metadata", "stale@9.9.9")
        # A plain directory without a metadata marker is left alone
        Dir.mkdir_p(tmpdir / "node_modules/plain-dir")

        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)
        File.exists?(tmpdir / "node_modules/stale").should be_false
        Dir.exists?(tmpdir / "node_modules/plain-dir").should be_true
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end

  it "installs a git dependency from a tag ref" do
    It.with_registry do |registry|
      repo = Path.new(Dir.tempdir, "zap-git-#{Random::Secure.hex(4)}")
      begin
        It.make_git_repo(repo, %({"name":"git-tag","version":"1.0.0","main":"index.js"}), {"index.js" => "v1"})
        Process.run("git", ["-C", repo.to_s, "tag", "v1.0.0"])

        It.install_project(registry, %({"name":"app","version":"1.0.0","dependencies":{"git-tag":"git+file://#{repo}#v1.0.0"}})) do |project|
          File.read(project / "node_modules/git-tag/index.js").should eq("v1")
        end
      ensure
        FileUtils.rm_rf(repo)
      end
    end
  end

  it "does not run the prepare script of registry dependencies" do
    It.with_registry do |registry|
      registry.add("prep-only", "1.0.0", It.pkg("prep-only", "1.0.0",
        scripts: {"prepare" => %(node -e "require('fs').writeFileSync('prepared.txt','yes')")}),
        {"index.js" => "p"})

      It.install_project(registry, %({"name":"app","version":"1.0.0","dependencies":{"prep-only":"1.0.0"}})) do |project|
        # prepare is only run for git dependencies (npm parity)
        File.exists?(project / "node_modules/prep-only/prepared.txt").should be_false
      end
    end
  end
  it "reinstalls offline with --prefer-offline without a lockfile" do
    It.with_registry do |registry|
      registry.add("off2", "1.0.0", It.pkg("off2", "1.0.0"), {"index.js" => "o"})

      tmpdir = Path.new(Dir.tempdir, "zap-it-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(tmpdir)
        File.write(tmpdir / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"off2":"^1.0.0"}}))
        File.write(tmpdir / ".npmrc", "registry=#{registry.base_url}/\n")
        config = Core::Config.new.copy_with(prefix: tmpdir.to_s, store_path: (tmpdir / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)

        registry.stop
        FileUtils.rm_rf(tmpdir / "node_modules")
        offline = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: false, prefer_offline: true)
        Commands::Install.run(config, offline, raise_on_failure: true, reporter: Reporter::Null.new)
        File.read(tmpdir / "node_modules/off2/index.js").should eq("o")
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end

end

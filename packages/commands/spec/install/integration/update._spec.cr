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
  it "bumps outside the range with --latest and preserves the modifier" do
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

        registry.add("pinned", "2.0.0", It.pkg("pinned", "2.0.0"), {"index.js" => "2.0.0"})
        latest = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true, update_all: true, update_latest: true)
        Commands::Install.run(config, latest, raise_on_failure: true, reporter: Reporter::Null.new)

        # The range is rewritten with the same modifier
        pkg = JSON.parse(File.read(tmpdir / "package.json"))
        pkg["dependencies"]["pinned"].as_s.should eq("^2.0.0")
        File.read(tmpdir / "node_modules/pinned/index.js").should eq("2.0.0")
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end

  it "keeps an exact version exact with --latest" do
    It.with_registry do |registry|
      registry.add("pinned", "1.0.0", It.pkg("pinned", "1.0.0"), {"index.js" => "1.0.0"})

      tmpdir = Path.new(Dir.tempdir, "zap-it-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(tmpdir)
        File.write(tmpdir / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"pinned":"1.0.0"}}))
        File.write(tmpdir / ".npmrc", "registry=#{registry.base_url}/\n")
        config = Core::Config.new.copy_with(prefix: tmpdir.to_s, store_path: (tmpdir / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)

        registry.add("pinned", "2.0.0", It.pkg("pinned", "2.0.0"), {"index.js" => "2.0.0"})
        latest = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true, update_all: true, update_latest: true)
        Commands::Install.run(config, latest, raise_on_failure: true, reporter: Reporter::Null.new)

        pkg = JSON.parse(File.read(tmpdir / "package.json"))
        pkg["dependencies"]["pinned"].as_s.should eq("2.0.0")
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end

  it "leaves complex ranges untouched with --latest" do
    It.with_registry do |registry|
      registry.add("pinned", "1.0.0", It.pkg("pinned", "1.0.0"), {"index.js" => "1.0.0"})
      registry.add("pinned", "1.5.0", It.pkg("pinned", "1.5.0"), {"index.js" => "1.5.0"})

      tmpdir = Path.new(Dir.tempdir, "zap-it-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(tmpdir)
        File.write(tmpdir / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"pinned":">=1.0.0 <2.0.0"}}))
        File.write(tmpdir / ".npmrc", "registry=#{registry.base_url}/\n")
        config = Core::Config.new.copy_with(prefix: tmpdir.to_s, store_path: (tmpdir / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)

        registry.add("pinned", "3.0.0", It.pkg("pinned", "3.0.0"), {"index.js" => "3.0.0"})
        latest = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true, update_all: true, update_latest: true)
        Commands::Install.run(config, latest, raise_on_failure: true, reporter: Reporter::Null.new)

        # The complex range cannot be rewritten, so it stays in-range
        pkg = JSON.parse(File.read(tmpdir / "package.json"))
        pkg["dependencies"]["pinned"].as_s.should eq(">=1.0.0 <2.0.0")
        File.read(tmpdir / "node_modules/pinned/index.js").should eq("1.5.0")
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end

  it "updates transitive dependencies with --recursive" do
    It.with_registry do |registry|
      registry.add("child", "1.0.0", It.pkg("child", "1.0.0"), {"index.js" => "1.0.0"})
      registry.add("parent", "1.0.0", It.pkg("parent", "1.0.0", dependencies: {"child" => "^1.0.0"}), {"index.js" => "parent"})

      tmpdir = Path.new(Dir.tempdir, "zap-it-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(tmpdir)
        File.write(tmpdir / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"parent":"1.0.0"}}))
        File.write(tmpdir / ".npmrc", "registry=#{registry.base_url}/\n")
        config = Core::Config.new.copy_with(prefix: tmpdir.to_s, store_path: (tmpdir / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)
        File.read(tmpdir / "node_modules/child/index.js").should eq("1.0.0")

        registry.add("child", "1.5.0", It.pkg("child", "1.5.0"), {"index.js" => "1.5.0"})
        recursive = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true, update_all: true, update_recursive: true)
        Commands::Install.run(config, recursive, raise_on_failure: true, reporter: Reporter::Null.new)
        File.read(tmpdir / "node_modules/child/index.js").should eq("1.5.0")
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end

  it "does not update transitive dependencies without --recursive" do
    It.with_registry do |registry|
      registry.add("child", "1.0.0", It.pkg("child", "1.0.0"), {"index.js" => "1.0.0"})
      registry.add("parent", "1.0.0", It.pkg("parent", "1.0.0", dependencies: {"child" => "^1.0.0"}), {"index.js" => "parent"})

      tmpdir = Path.new(Dir.tempdir, "zap-it-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(tmpdir)
        File.write(tmpdir / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"parent":"1.0.0"}}))
        File.write(tmpdir / ".npmrc", "registry=#{registry.base_url}/\n")
        config = Core::Config.new.copy_with(prefix: tmpdir.to_s, store_path: (tmpdir / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)

        registry.add("child", "1.5.0", It.pkg("child", "1.5.0"), {"index.js" => "1.5.0"})
        plain = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true, update_all: true)
        Commands::Install.run(config, plain, raise_on_failure: true, reporter: Reporter::Null.new)
        File.read(tmpdir / "node_modules/child/index.js").should eq("1.0.0")
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end

  it "sets a new range with zap up pkg@range" do
    It.with_registry do |registry|
      registry.add("pinned", "1.0.0", It.pkg("pinned", "1.0.0"), {"index.js" => "1.0.0"})

      tmpdir = Path.new(Dir.tempdir, "zap-it-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(tmpdir)
        File.write(tmpdir / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"pinned":"1.0.0"}}))
        File.write(tmpdir / ".npmrc", "registry=#{registry.base_url}/\n")
        config = Core::Config.new.copy_with(prefix: tmpdir.to_s, store_path: (tmpdir / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)

        registry.add("pinned", "2.0.0", It.pkg("pinned", "2.0.0"), {"index.js" => "2.0.0"})
        targeted = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true, updated_packages: ["pinned@^2.0.0"])
        Commands::Install.run(config, targeted, raise_on_failure: true, reporter: Reporter::Null.new)

        pkg = JSON.parse(File.read(tmpdir / "package.json"))
        pkg["dependencies"]["pinned"].as_s.should eq("^2.0.0")
        File.read(tmpdir / "node_modules/pinned/index.js").should eq("2.0.0")
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end

  it "does not pick prereleases when updating" do
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
        registry.add("pinned", "2.0.0-beta.1", It.pkg("pinned", "2.0.0-beta.1"), {"index.js" => "beta"})
        latest = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true, update_all: true, update_latest: true)
        Commands::Install.run(config, latest, raise_on_failure: true, reporter: Reporter::Null.new)

        # The prerelease is not picked even with --latest
        File.read(tmpdir / "node_modules/pinned/index.js").should eq("1.5.0")
        pkg = JSON.parse(File.read(tmpdir / "package.json"))
        pkg["dependencies"]["pinned"].as_s.should eq("^1.5.0")
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end

  it "leaves the manifest byte-identical when an update changes nothing" do
    It.with_registry do |registry|
      registry.add("pinned", "1.0.0", It.pkg("pinned", "1.0.0"), {"index.js" => "1.0.0"})

      tmpdir = Path.new(Dir.tempdir, "zap-it-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(tmpdir)
        manifest = %({"name":"app","version":"1.0.0","dependencies":{"pinned":"^1.0.0"}})
        File.write(tmpdir / "package.json", manifest)
        File.write(tmpdir / ".npmrc", "registry=#{registry.base_url}/\n")
        config = Core::Config.new.copy_with(prefix: tmpdir.to_s, store_path: (tmpdir / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)

        plain = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true, update_all: true)
        Commands::Install.run(config, plain, raise_on_failure: true, reporter: Reporter::Null.new)
        File.read(tmpdir / "package.json").should eq(manifest)
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end

  it "rewrites only the named package with zap up pkg --latest" do
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

        registry.add("bump", "2.0.0", It.pkg("bump", "2.0.0"), {"index.js" => "2.0.0"})
        targeted = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true, updated_packages: ["bump"], update_latest: true)
        Commands::Install.run(config, targeted, raise_on_failure: true, reporter: Reporter::Null.new)

        pkg = JSON.parse(File.read(tmpdir / "package.json"))
        pkg["dependencies"]["bump"].as_s.should eq("^2.0.0")
        # The unrelated dependency is untouched
        pkg["dependencies"]["stay"].as_s.should eq("^1.0.0")
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end

  it "updates the subtree of a named package with zap up pkg --recursive" do
    It.with_registry do |registry|
      registry.add("child", "1.0.0", It.pkg("child", "1.0.0"), {"index.js" => "1.0.0"})
      registry.add("parent", "1.0.0", It.pkg("parent", "1.0.0", dependencies: {"child" => "^1.0.0"}), {"index.js" => "parent"})

      tmpdir = Path.new(Dir.tempdir, "zap-it-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(tmpdir)
        File.write(tmpdir / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"parent":"1.0.0"}}))
        File.write(tmpdir / ".npmrc", "registry=#{registry.base_url}/\n")
        config = Core::Config.new.copy_with(prefix: tmpdir.to_s, store_path: (tmpdir / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)

        registry.add("child", "1.5.0", It.pkg("child", "1.5.0"), {"index.js" => "1.5.0"})
        targeted = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true, updated_packages: ["parent"], update_recursive: true)
        Commands::Install.run(config, targeted, raise_on_failure: true, reporter: Reporter::Null.new)
        File.read(tmpdir / "node_modules/child/index.js").should eq("1.5.0")
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end

  it "preserves the <= range with --latest (yarn upgrade port)" do
    It.with_registry do |registry|
      registry.add("pinned", "1.0.0", It.pkg("pinned", "1.0.0"), {"index.js" => "1.0.0"})

      tmpdir = Path.new(Dir.tempdir, "zap-it-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(tmpdir)
        File.write(tmpdir / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"pinned":"<=1.0.0"}}))
        File.write(tmpdir / ".npmrc", "registry=#{registry.base_url}/\n")
        config = Core::Config.new.copy_with(prefix: tmpdir.to_s, store_path: (tmpdir / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)

        registry.add("pinned", "2.0.0", It.pkg("pinned", "2.0.0"), {"index.js" => "2.0.0"})
        latest = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true, update_all: true, update_latest: true)
        Commands::Install.run(config, latest, raise_on_failure: true, reporter: Reporter::Null.new)

        pkg = JSON.parse(File.read(tmpdir / "package.json"))
        pkg["dependencies"]["pinned"].as_s.should eq("<=2.0.0")
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end

  it "preserves the >= range with --latest" do
    It.with_registry do |registry|
      registry.add("pinned", "1.0.0", It.pkg("pinned", "1.0.0"), {"index.js" => "1.0.0"})

      tmpdir = Path.new(Dir.tempdir, "zap-it-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(tmpdir)
        File.write(tmpdir / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"pinned":">=1.0.0"}}))
        File.write(tmpdir / ".npmrc", "registry=#{registry.base_url}/\n")
        config = Core::Config.new.copy_with(prefix: tmpdir.to_s, store_path: (tmpdir / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)

        registry.add("pinned", "2.0.0", It.pkg("pinned", "2.0.0"), {"index.js" => "2.0.0"})
        latest = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true, update_all: true, update_latest: true)
        Commands::Install.run(config, latest, raise_on_failure: true, reporter: Reporter::Null.new)

        pkg = JSON.parse(File.read(tmpdir / "package.json"))
        pkg["dependencies"]["pinned"].as_s.should eq(">=2.0.0")
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end

  it "does not downgrade a prerelease with --latest (yarn upgrade port)" do
    It.with_registry do |registry|
      registry.add("react-refetch", "1.0.3-0", It.pkg("react-refetch", "1.0.3-0"), {"index.js" => "beta"})

      tmpdir = Path.new(Dir.tempdir, "zap-it-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(tmpdir)
        File.write(tmpdir / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"react-refetch":"^1.0.3-0"}}))
        File.write(tmpdir / ".npmrc", "registry=#{registry.base_url}/\n")
        config = Core::Config.new.copy_with(prefix: tmpdir.to_s, store_path: (tmpdir / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)

        latest = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true, update_all: true, update_latest: true)
        Commands::Install.run(config, latest, raise_on_failure: true, reporter: Reporter::Null.new)

        File.read(tmpdir / "node_modules/react-refetch/index.js").should eq("beta")
        pkg = JSON.parse(File.read(tmpdir / "package.json"))
        pkg["dependencies"]["react-refetch"].as_s.should eq("^1.0.3-0")
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end

  it "rewrites devDependencies with --latest" do
    It.with_registry do |registry|
      registry.add("pinned", "1.0.0", It.pkg("pinned", "1.0.0"), {"index.js" => "1.0.0"})

      tmpdir = Path.new(Dir.tempdir, "zap-it-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(tmpdir)
        File.write(tmpdir / "package.json", %({"name":"app","version":"1.0.0","devDependencies":{"pinned":"^1.0.0"}}))
        File.write(tmpdir / ".npmrc", "registry=#{registry.base_url}/\n")
        config = Core::Config.new.copy_with(prefix: tmpdir.to_s, store_path: (tmpdir / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)

        registry.add("pinned", "2.0.0", It.pkg("pinned", "2.0.0"), {"index.js" => "2.0.0"})
        latest = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true, update_all: true, update_latest: true)
        Commands::Install.run(config, latest, raise_on_failure: true, reporter: Reporter::Null.new)

        pkg = JSON.parse(File.read(tmpdir / "package.json"))
        pkg["devDependencies"]["pinned"].as_s.should eq("^2.0.0")
        File.read(tmpdir / "node_modules/pinned/index.js").should eq("2.0.0")
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end

  it "leaves the manifest byte-identical when --latest finds nothing new" do
    It.with_registry do |registry|
      registry.add("pinned", "1.0.0", It.pkg("pinned", "1.0.0"), {"index.js" => "1.0.0"})

      tmpdir = Path.new(Dir.tempdir, "zap-it-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(tmpdir)
        manifest = %({"name":"app","version":"1.0.0","dependencies":{"pinned":"^1.0.0"}})
        File.write(tmpdir / "package.json", manifest)
        File.write(tmpdir / ".npmrc", "registry=#{registry.base_url}/\n")
        config = Core::Config.new.copy_with(prefix: tmpdir.to_s, store_path: (tmpdir / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)

        latest = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true, update_all: true, update_latest: true)
        Commands::Install.run(config, latest, raise_on_failure: true, reporter: Reporter::Null.new)
        File.read(tmpdir / "package.json").should eq(manifest)
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end

  it "leaves the manifest byte-identical when re-running zap up pkg@range" do
    It.with_registry do |registry|
      registry.add("pinned", "1.0.0", It.pkg("pinned", "1.0.0"), {"index.js" => "1.0.0"})

      tmpdir = Path.new(Dir.tempdir, "zap-it-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(tmpdir)
        manifest = %({"name":"app","version":"1.0.0","dependencies":{"pinned":"1.0.0"}})
        File.write(tmpdir / "package.json", manifest)
        File.write(tmpdir / ".npmrc", "registry=#{registry.base_url}/\n")
        config = Core::Config.new.copy_with(prefix: tmpdir.to_s, store_path: (tmpdir / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)

        # The range is already 1.0.0; re-running must not touch the manifest
        targeted = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true, updated_packages: ["pinned@1.0.0"])
        Commands::Install.run(config, targeted, raise_on_failure: true, reporter: Reporter::Null.new)
        File.read(tmpdir / "package.json").should eq(manifest)
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end

  it "preserves the ~ range with --latest" do
    It.with_registry do |registry|
      registry.add("pinned", "1.0.0", It.pkg("pinned", "1.0.0"), {"index.js" => "1.0.0"})

      tmpdir = Path.new(Dir.tempdir, "zap-it-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(tmpdir)
        File.write(tmpdir / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"pinned":"~1.0.0"}}))
        File.write(tmpdir / ".npmrc", "registry=#{registry.base_url}/\n")
        config = Core::Config.new.copy_with(prefix: tmpdir.to_s, store_path: (tmpdir / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)

        registry.add("pinned", "1.9.0", It.pkg("pinned", "1.9.0"), {"index.js" => "1.9.0"})
        registry.add("pinned", "2.0.0", It.pkg("pinned", "2.0.0"), {"index.js" => "2.0.0"})
        latest = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true, update_all: true, update_latest: true)
        Commands::Install.run(config, latest, raise_on_failure: true, reporter: Reporter::Null.new)

        pkg = JSON.parse(File.read(tmpdir / "package.json"))
        pkg["dependencies"]["pinned"].as_s.should eq("~2.0.0")
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end

  it "keeps npm aliases intact when an update rewrites the manifest" do
    It.with_registry do |registry|
      registry.add("real-pkg", "1.0.0", It.pkg("real-pkg", "1.0.0"), {"index.js" => "1.0.0"})
      registry.add("bump", "1.0.0", It.pkg("bump", "1.0.0"), {"index.js" => "1.0.0"})

      tmpdir = Path.new(Dir.tempdir, "zap-it-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(tmpdir)
        File.write(tmpdir / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"my-alias":"npm:real-pkg@1.0.0","bump":"^1.0.0"}}))
        File.write(tmpdir / ".npmrc", "registry=#{registry.base_url}/\n")
        config = Core::Config.new.copy_with(prefix: tmpdir.to_s, store_path: (tmpdir / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)

        registry.add("bump", "2.0.0", It.pkg("bump", "2.0.0"), {"index.js" => "2.0.0"})
        latest = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true, update_all: true, update_latest: true)
        Commands::Install.run(config, latest, raise_on_failure: true, reporter: Reporter::Null.new)

        pkg = JSON.parse(File.read(tmpdir / "package.json"))
        pkg["dependencies"]["bump"].as_s.should eq("^2.0.0")
        pkg["dependencies"]["my-alias"].as_s.should eq("npm:real-pkg@1.0.0")
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end

  it "rewrites every workspace manifest with --latest, not only the command scope" do
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

        registry.add("pinned", "2.0.0", It.pkg("pinned", "2.0.0"), {"index.js" => "2.0.0"})
        latest = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true, update_all: true, update_latest: true)
        Commands::Install.run(config, latest, raise_on_failure: true, reporter: Reporter::Null.new)

        JSON.parse(File.read(ws_root / "packages/a/package.json"))["dependencies"]["pinned"].as_s.should eq("^2.0.0")
        JSON.parse(File.read(ws_root / "packages/b/package.json"))["dependencies"]["pinned"].as_s.should eq("^2.0.0")
      ensure
        FileUtils.rm_rf(ws_root)
      end
    end
  end

  it "re-resolves every workspace for pkg@range updates, not only the command scope" do
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

        registry.add("pinned", "1.2.0", It.pkg("pinned", "1.2.0"), {"index.js" => "1.2.0"})
        up = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true, updated_packages: ["pinned@^1.2.0"])
        Commands::Install.run(config, up, raise_on_failure: true, reporter: Reporter::Null.new)

        JSON.parse(File.read(ws_root / "packages/a/package.json"))["dependencies"]["pinned"].as_s.should eq("^1.2.0")
        JSON.parse(File.read(ws_root / "packages/b/package.json"))["dependencies"]["pinned"].as_s.should eq("^1.2.0")
        lockfile = Data::Lockfile.new(ws_root)
        lockfile.roots["ws-a"].dependency_specifier?("pinned").should eq("1.2.0")
        lockfile.roots["ws-b"].dependency_specifier?("pinned").should eq("1.2.0")
      ensure
        FileUtils.rm_rf(ws_root)
      end
    end
  end

  it "updates a dep declared in both dependencies and devDependencies with pkg@range" do
    It.with_registry do |registry|
      registry.add("pinned", "1.0.0", It.pkg("pinned", "1.0.0"), {"index.js" => "1.0.0"})

      tmpdir = Path.new(Dir.tempdir, "zap-it-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(tmpdir)
        File.write(tmpdir / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"pinned":"^1.0.0"},"devDependencies":{"pinned":"^1.0.0"}}))
        File.write(tmpdir / ".npmrc", "registry=#{registry.base_url}/\n")
        config = Core::Config.new.copy_with(prefix: tmpdir.to_s, store_path: (tmpdir / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)

        registry.add("pinned", "1.2.0", It.pkg("pinned", "1.2.0"), {"index.js" => "1.2.0"})
        up = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true, updated_packages: ["pinned@^1.2.0"])
        Commands::Install.run(config, up, raise_on_failure: true, reporter: Reporter::Null.new)

        pkg = JSON.parse(File.read(tmpdir / "package.json"))
        pkg["dependencies"]["pinned"].as_s.should eq("^1.2.0")
        pkg["devDependencies"]["pinned"].as_s.should eq("^1.2.0")
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end

  it "updates an optionalDependencies entry with pkg@range" do
    It.with_registry do |registry|
      registry.add("pinned", "1.0.0", It.pkg("pinned", "1.0.0"), {"index.js" => "1.0.0"})

      tmpdir = Path.new(Dir.tempdir, "zap-it-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(tmpdir)
        File.write(tmpdir / "package.json", %({"name":"app","version":"1.0.0","optionalDependencies":{"pinned":"^1.0.0"}}))
        File.write(tmpdir / ".npmrc", "registry=#{registry.base_url}/\n")
        config = Core::Config.new.copy_with(prefix: tmpdir.to_s, store_path: (tmpdir / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)

        registry.add("pinned", "1.2.0", It.pkg("pinned", "1.2.0"), {"index.js" => "1.2.0"})
        up = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true, updated_packages: ["pinned@^1.2.0"])
        Commands::Install.run(config, up, raise_on_failure: true, reporter: Reporter::Null.new)

        pkg = JSON.parse(File.read(tmpdir / "package.json"))
        pkg["optionalDependencies"]["pinned"].as_s.should eq("^1.2.0")
        File.read(tmpdir / "node_modules/pinned/index.js").should eq("1.2.0")
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end

  it "keeps transitive dependencies within their declared range with --latest --recursive" do
    It.with_registry do |registry|
      registry.add("child", "1.0.0", It.pkg("child", "1.0.0"), {"index.js" => "1.0.0"})
      registry.add("parent", "1.0.0", It.pkg("parent", "1.0.0", dependencies: {"child" => "^1.0.0"}), {"index.js" => "parent"})

      tmpdir = Path.new(Dir.tempdir, "zap-it-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(tmpdir)
        File.write(tmpdir / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"parent":"1.0.0"}}))
        File.write(tmpdir / ".npmrc", "registry=#{registry.base_url}/\n")
        config = Core::Config.new.copy_with(prefix: tmpdir.to_s, store_path: (tmpdir / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)

        registry.add("child", "1.5.0", It.pkg("child", "1.5.0"), {"index.js" => "1.5.0"})
        registry.add("child", "2.0.0", It.pkg("child", "2.0.0"), {"index.js" => "2.0.0"})
        combo = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true, update_all: true, update_latest: true, update_recursive: true)
        Commands::Install.run(config, combo, raise_on_failure: true, reporter: Reporter::Null.new)

        # --latest only bumps direct dependencies; the transitive re-resolution
        # stays within the declared range, never outside it
        File.read(tmpdir / "node_modules/child/index.js").should eq("1.5.0")
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end

  it "applies --latest to overridden direct dependencies without crashing" do
    It.with_registry do |registry|
      registry.add("dep", "1.0.0", It.pkg("dep", "1.0.0"), {"index.js" => "1.0.0"})
      registry.add("dep", "2.0.0", It.pkg("dep", "2.0.0"), {"index.js" => "2.0.0"})

      tmpdir = Path.new(Dir.tempdir, "zap-it-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(tmpdir)
        File.write(tmpdir / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"dep":"^1.0.0"},"overrides":{"dep":"^1.0.0"}}))
        File.write(tmpdir / ".npmrc", "registry=#{registry.base_url}/\n")
        config = Core::Config.new.copy_with(prefix: tmpdir.to_s, store_path: (tmpdir / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)

        latest = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true, update_all: true, update_latest: true)
        Commands::Install.run(config, latest, raise_on_failure: true, reporter: Reporter::Null.new)

        # The override resolves in lockstep with the direct dependency
        File.read(tmpdir / "node_modules/dep/index.js").should eq("2.0.0")
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end

  it "keeps the overridden version when pkg@range changes the declared range" do
    It.with_registry do |registry|
      registry.add("dep", "1.0.0", It.pkg("dep", "1.0.0"), {"index.js" => "1.0.0"})
      registry.add("dep", "2.0.0", It.pkg("dep", "2.0.0"), {"index.js" => "2.0.0"})

      tmpdir = Path.new(Dir.tempdir, "zap-it-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(tmpdir)
        File.write(tmpdir / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"dep":"^1.0.0"},"overrides":{"dep":"^1.0.0"}}))
        File.write(tmpdir / ".npmrc", "registry=#{registry.base_url}/\n")
        config = Core::Config.new.copy_with(prefix: tmpdir.to_s, store_path: (tmpdir / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)

        up = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true, updated_packages: ["dep@^2.0.0"])
        Commands::Install.run(config, up, raise_on_failure: true, reporter: Reporter::Null.new)

        # The manifest range updates but the override keeps its version (npm
        # parity: the override wins), and the update must not crash.
        JSON.parse(File.read(tmpdir / "package.json"))["dependencies"]["dep"].as_s.should eq("^2.0.0")
        File.read(tmpdir / "node_modules/dep/index.js").should eq("1.0.0")
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end

  it "does not loop forever on a diamond dependency graph with --recursive" do
    It.with_registry do |registry|
      registry.add("d", "1.0.0", It.pkg("d", "1.0.0"), {"index.js" => "d"})
      registry.add("b", "1.0.0", It.pkg("b", "1.0.0", dependencies: {"d" => "^1.0.0"}), {"index.js" => "b"})
      registry.add("c", "1.0.0", It.pkg("c", "1.0.0", dependencies: {"d" => "^1.0.0"}), {"index.js" => "c"})
      registry.add("a", "1.0.0", It.pkg("a", "1.0.0", dependencies: {"b" => "^1.0.0", "c" => "^1.0.0"}), {"index.js" => "a"})

      tmpdir = Path.new(Dir.tempdir, "zap-it-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(tmpdir)
        File.write(tmpdir / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"a":"1.0.0"}}))
        File.write(tmpdir / ".npmrc", "registry=#{registry.base_url}/\n")
        config = Core::Config.new.copy_with(prefix: tmpdir.to_s, store_path: (tmpdir / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)

        registry.add("d", "1.5.0", It.pkg("d", "1.5.0"), {"index.js" => "d2"})
        recursive = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true, update_all: true, update_recursive: true)
        Commands::Install.run(config, recursive, raise_on_failure: true, reporter: Reporter::Null.new)

        # The recursion guard must trip on the shared transitive, not loop
        File.read(tmpdir / "node_modules/d/index.js").should eq("d2")
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end

  # Ports from yarn berry (up.test.ts) and pnpm (installing/commands/test/update).
  it "upgrades all dependencies matching a glob pattern (yarn berry port)" do
    It.with_registry do |registry|
      registry.add("@scope/alpha", "1.0.0", It.pkg("@scope/alpha", "1.0.0"), {"index.js" => "1.0.0"})
      registry.add("@scope/beta", "1.0.0", It.pkg("@scope/beta", "1.0.0"), {"index.js" => "1.0.0"})
      registry.add("plain", "1.0.0", It.pkg("plain", "1.0.0"), {"index.js" => "1.0.0"})

      tmpdir = Path.new(Dir.tempdir, "zap-it-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(tmpdir)
        File.write(tmpdir / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"@scope/alpha":"^1.0.0","@scope/beta":"^1.0.0","plain":"^1.0.0"}}))
        File.write(tmpdir / ".npmrc", "registry=#{registry.base_url}/\n")
        config = Core::Config.new.copy_with(prefix: tmpdir.to_s, store_path: (tmpdir / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)

        registry.add("@scope/alpha", "2.0.0", It.pkg("@scope/alpha", "2.0.0"), {"index.js" => "2.0.0"})
        registry.add("@scope/beta", "2.0.0", It.pkg("@scope/beta", "2.0.0"), {"index.js" => "2.0.0"})
        registry.add("plain", "2.0.0", It.pkg("plain", "2.0.0"), {"index.js" => "2.0.0"})

        up = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true, update_latest: true, updated_packages: ["@scope/*"])
        Commands::Install.run(config, up, raise_on_failure: true, reporter: Reporter::Null.new)

        pkg = JSON.parse(File.read(tmpdir / "package.json"))
        pkg["dependencies"]["@scope/alpha"].as_s.should eq("^2.0.0")
        pkg["dependencies"]["@scope/beta"].as_s.should eq("^2.0.0")
        pkg["dependencies"]["plain"].as_s.should eq("^1.0.0")
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end

  it "upgrades all dependencies matching a glob pattern with a range (yarn berry port)" do
    It.with_registry do |registry|
      registry.add("@scope/alpha", "1.0.0", It.pkg("@scope/alpha", "1.0.0"), {"index.js" => "1.0.0"})
      registry.add("@scope/alpha", "2.0.0", It.pkg("@scope/alpha", "2.0.0"), {"index.js" => "2.0.0"})
      registry.add("@scope/beta", "1.0.0", It.pkg("@scope/beta", "1.0.0"), {"index.js" => "1.0.0"})
      registry.add("@scope/beta", "2.0.0", It.pkg("@scope/beta", "2.0.0"), {"index.js" => "2.0.0"})

      tmpdir = Path.new(Dir.tempdir, "zap-it-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(tmpdir)
        File.write(tmpdir / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"@scope/alpha":"^2.0.0","@scope/beta":"^2.0.0"}}))
        File.write(tmpdir / ".npmrc", "registry=#{registry.base_url}/\n")
        config = Core::Config.new.copy_with(prefix: tmpdir.to_s, store_path: (tmpdir / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)

        up = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true, updated_packages: ["@scope/*@1.0.0"])
        Commands::Install.run(config, up, raise_on_failure: true, reporter: Reporter::Null.new)

        pkg = JSON.parse(File.read(tmpdir / "package.json"))
        pkg["dependencies"]["@scope/alpha"].as_s.should eq("1.0.0")
        pkg["dependencies"]["@scope/beta"].as_s.should eq("1.0.0")
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end

  it "updates everything except a negated glob pattern (pnpm port)" do
    It.with_registry do |registry|
      registry.add("peer-a", "1.0.0", It.pkg("peer-a", "1.0.0"), {"index.js" => "1.0.0"})
      registry.add("foo", "1.0.0", It.pkg("foo", "1.0.0"), {"index.js" => "1.0.0"})

      tmpdir = Path.new(Dir.tempdir, "zap-it-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(tmpdir)
        File.write(tmpdir / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"peer-a":"1.0.0","foo":"1.0.0"}}))
        File.write(tmpdir / ".npmrc", "registry=#{registry.base_url}/\n")
        config = Core::Config.new.copy_with(prefix: tmpdir.to_s, store_path: (tmpdir / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)

        registry.add("peer-a", "2.0.0", It.pkg("peer-a", "2.0.0"), {"index.js" => "2.0.0"})
        registry.add("foo", "2.0.0", It.pkg("foo", "2.0.0"), {"index.js" => "2.0.0"})

        up = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true, update_latest: true, updated_packages: ["!peer-a"])
        Commands::Install.run(config, up, raise_on_failure: true, reporter: Reporter::Null.new)

        pkg = JSON.parse(File.read(tmpdir / "package.json"))
        pkg["dependencies"]["peer-a"].as_s.should eq("1.0.0")
        # the exact specifier stays exact (zap preserves the modifier)
        pkg["dependencies"]["foo"].as_s.should eq("2.0.0")
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end

  it "mixes positive and negated patterns: only the positives update (pnpm port)" do
    It.with_registry do |registry|
      registry.add("peer-a", "1.0.0", It.pkg("peer-a", "1.0.0"), {"index.js" => "1.0.0"})
      registry.add("other", "1.0.0", It.pkg("other", "1.0.0"), {"index.js" => "1.0.0"})
      registry.add("foo", "1.0.0", It.pkg("foo", "1.0.0"), {"index.js" => "1.0.0"})

      tmpdir = Path.new(Dir.tempdir, "zap-it-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(tmpdir)
        File.write(tmpdir / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"peer-a":"1.0.0","other":"1.0.0","foo":"1.0.0"}}))
        File.write(tmpdir / ".npmrc", "registry=#{registry.base_url}/\n")
        config = Core::Config.new.copy_with(prefix: tmpdir.to_s, store_path: (tmpdir / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)

        registry.add("peer-a", "2.0.0", It.pkg("peer-a", "2.0.0"), {"index.js" => "2.0.0"})
        registry.add("other", "2.0.0", It.pkg("other", "2.0.0"), {"index.js" => "2.0.0"})
        registry.add("foo", "2.0.0", It.pkg("foo", "2.0.0"), {"index.js" => "2.0.0"})

        up = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true, update_latest: true, updated_packages: ["foo", "!peer-a"])
        Commands::Install.run(config, up, raise_on_failure: true, reporter: Reporter::Null.new)

        pkg = JSON.parse(File.read(tmpdir / "package.json"))
        pkg["dependencies"]["foo"].as_s.should eq("2.0.0")
        pkg["dependencies"]["peer-a"].as_s.should eq("1.0.0")
        pkg["dependencies"]["other"].as_s.should eq("1.0.0")
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end

  it "does not touch the manifest or lockfile with save disabled (pnpm port)" do
    It.with_registry do |registry|
      registry.add("pinned", "1.0.0", It.pkg("pinned", "1.0.0"), {"index.js" => "1.0.0"})

      tmpdir = Path.new(Dir.tempdir, "zap-it-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(tmpdir)
        manifest = %({"name":"app","version":"1.0.0","dependencies":{"pinned":"^1.0.0"}})
        File.write(tmpdir / "package.json", manifest)
        File.write(tmpdir / ".npmrc", "registry=#{registry.base_url}/\n")
        config = Core::Config.new.copy_with(prefix: tmpdir.to_s, store_path: (tmpdir / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)
        lockfile_before = File.read(tmpdir / "zap.lock")

        registry.add("pinned", "2.0.0", It.pkg("pinned", "2.0.0"), {"index.js" => "2.0.0"})
        no_save = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: false, update_all: true, update_latest: true)
        Commands::Install.run(config, no_save, raise_on_failure: true, reporter: Reporter::Null.new)

        File.read(tmpdir / "package.json").should eq(manifest)
        File.read(tmpdir / "zap.lock").should eq(lockfile_before)
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end

  it "resolves an npm: alias to the latest of the aliased package with --latest (pnpm port)" do
    It.with_registry do |registry|
      registry.add("real", "1.0.0", It.pkg("real", "1.0.0"), {"index.js" => "1.0.0"})

      tmpdir = Path.new(Dir.tempdir, "zap-it-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(tmpdir)
        File.write(tmpdir / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"foo-alias":"npm:real@~1.0.0"}}))
        File.write(tmpdir / ".npmrc", "registry=#{registry.base_url}/\n")
        config = Core::Config.new.copy_with(prefix: tmpdir.to_s, store_path: (tmpdir / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)

        registry.add("real", "100.1.0", It.pkg("real", "100.1.0"), {"index.js" => "100.1.0"})
        up = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true, update_all: true, update_latest: true)
        Commands::Install.run(config, up, raise_on_failure: true, reporter: Reporter::Null.new)

        pkg = JSON.parse(File.read(tmpdir / "package.json"))
        pkg["dependencies"]["foo-alias"].as_s.should eq("npm:real@~100.1.0")
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end

  it "does not update dist-tag specifiers without --latest (pnpm port)" do
    It.with_registry do |registry|
      registry.add("tagged", "1.0.0", It.pkg("tagged", "1.0.0"), {"index.js" => "1.0.0"})

      tmpdir = Path.new(Dir.tempdir, "zap-it-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(tmpdir)
        manifest = %({"name":"app","version":"1.0.0","dependencies":{"tagged":"latest"}})
        File.write(tmpdir / "package.json", manifest)
        File.write(tmpdir / ".npmrc", "registry=#{registry.base_url}/\n")
        config = Core::Config.new.copy_with(prefix: tmpdir.to_s, store_path: (tmpdir / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)

        registry.add("tagged", "2.0.0", It.pkg("tagged", "2.0.0"), {"index.js" => "2.0.0"})
        up = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true, update_all: true)
        Commands::Install.run(config, up, raise_on_failure: true, reporter: Reporter::Null.new)

        File.read(tmpdir / "package.json").should eq(manifest)
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end

  it "updates dependencies with an empty declared specifier (pnpm port)" do
    It.with_registry do |registry|
      registry.add("foo", "1.0.0", It.pkg("foo", "1.0.0"), {"index.js" => "1.0.0"})

      tmpdir = Path.new(Dir.tempdir, "zap-it-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(tmpdir)
        File.write(tmpdir / "package.json", %({"name":"app","version":"1.0.0","devDependencies":{"foo":""}}))
        File.write(tmpdir / ".npmrc", "registry=#{registry.base_url}/\n")
        config = Core::Config.new.copy_with(prefix: tmpdir.to_s, store_path: (tmpdir / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)

        registry.add("foo", "2.0.0", It.pkg("foo", "2.0.0"), {"index.js" => "2.0.0"})
        up = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true, update_all: true, update_latest: true)
        Commands::Install.run(config, up, raise_on_failure: true, reporter: Reporter::Null.new)

        lockfile = Data::Lockfile.new(tmpdir)
        lockfile.packages.keys.should contain("foo@2.0.0")
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end

end

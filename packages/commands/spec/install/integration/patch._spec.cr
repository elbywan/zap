require "../../../patch/patch"
require "../../../patch/config"
require "./spec_helper"


# zap patch: extract an installed package, edit it, commit the changes as a
# patch and have the patch applied on the next install.
describe "patch", tags: "integration" do
  it "extracts, commits and applies a patch" do
    It.with_registry do |registry|
      registry.add("a", "1.0.0", It.pkg("a", "1.0.0"), {"index.js" => "const x = 1;\nconsole.log(x);\n"})

      tmpdir = Path.new(Dir.tempdir, "zap-it-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(tmpdir)
        File.write(tmpdir / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"a":"1.0.0"}}))
        File.write(tmpdir / ".npmrc", "registry=#{registry.base_url}/\n")
        config = Core::Config.new.copy_with(prefix: tmpdir.to_s, store_path: (tmpdir / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)
        File.read(tmpdir / "node_modules/a/index.js").should eq("const x = 1;\nconsole.log(x);\n")
        # One project-level state file, no per-package marker files
        File.exists?(tmpdir / "node_modules/.zap-state").should be_true
        File.exists?(tmpdir / "node_modules/a/.zap.metadata").should be_false

        old_argv = ARGV.dup
        begin
          # zap patch a@1.0.0 extracts the package to a temp directory
          output = IO::Memory.new
          ARGV.replace(["a@1.0.0"])
          Commands::Patch.run(config, Commands::Patch::Config.new, output_io: output)
          dir_line = output.to_s.lines.find { |l| l.starts_with?("Patched package directory: ") }
          patch_dir = Path.new(dir_line.not_nil!.split(": ", 2)[1].strip)
          File.exists?(patch_dir / ".zap-patch.json").should be_true
          File.read(patch_dir / "index.js").should eq("const x = 1;\nconsole.log(x);\n")

          # Edit the extracted copy, then commit the patch
          File.write(patch_dir / "index.js", "const x = 42;\nconsole.log(x);\n// patched\n")
          ARGV.replace([patch_dir.to_s])
          Commands::Patch.run(config, Commands::Patch::Config.new.copy_with(commit: true), output_io: output)

          # The patch file is written and registered in package.json
          patch_path = tmpdir / "patches/a@1.0.0.patch"
          File.exists?(patch_path).should be_true
          pkg_json = JSON.parse(File.read(tmpdir / "package.json"))
          pkg_json["zap"]["patched_dependencies"]["a@1.0.0"].should eq("patches/a@1.0.0.patch")

          # patch-commit re-installed the package right away (no zap i)
          File.read(tmpdir / "node_modules/a/index.js").should eq("const x = 42;\nconsole.log(x);\n// patched\n")

          # patch-commit refreshed the lockfile: a frozen install passes
          Commands::Install.run(config, ic.copy_with(frozen_lockfile: true), raise_on_failure: true, reporter: Reporter::Null.new)
          File.read(tmpdir / "node_modules/a/index.js").should eq("const x = 42;\nconsole.log(x);\n// patched\n")

          # A fresh install applies the patch to the linked copy, and the
          # store copy stays pristine (the classic strategy hardlinks files).
          FileUtils.rm_rf(tmpdir / "node_modules")
          Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)
          File.read(tmpdir / "node_modules/a/index.js").should eq("const x = 42;\nconsole.log(x);\n// patched\n")
          store_pkg = ::Store.new(config.store_path).package_path(Data::Lockfile.new(tmpdir.to_s).get_package("a", "1.0.0"))
          File.read(store_pkg / "index.js").should eq("const x = 1;\nconsole.log(x);\n")
        ensure
          ARGV.replace(old_argv)
        end
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end

  it "applies patches with the isolated strategy" do
    It.with_registry do |registry|
      registry.add("a", "1.0.0", It.pkg("a", "1.0.0"), {"index.js" => "one\n"})

      tmpdir = Path.new(Dir.tempdir, "zap-it-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(tmpdir)
        File.write(tmpdir / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"a":"1.0.0"},"zap":{"strategy":"isolated","patched_dependencies":{"a@1.0.0":"patches/a.patch"}}}))
        File.write(tmpdir / ".npmrc", "registry=#{registry.base_url}/\n")
        Dir.mkdir_p(tmpdir / "patches")
        File.write(tmpdir / "patches/a.patch", "--- a/index.js\n+++ b/index.js\n@@ -1,1 +1,1 @@\n-one\n+deux\n")
        config = Core::Config.new.copy_with(prefix: tmpdir.to_s, store_path: (tmpdir / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)
        File.read(tmpdir / "node_modules/a/index.js").should eq("deux\n")
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end

  it "fails when a registered patch does not match" do
    It.with_registry do |registry|
      registry.add("a", "1.0.0", It.pkg("a", "1.0.0"), {"index.js" => "one\n"})

      tmpdir = Path.new(Dir.tempdir, "zap-it-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(tmpdir)
        File.write(tmpdir / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"a":"1.0.0"},"zap":{"patched_dependencies":{"a@1.0.0":"patches/a.patch"}}}))
        File.write(tmpdir / ".npmrc", "registry=#{registry.base_url}/\n")
        Dir.mkdir_p(tmpdir / "patches")
        File.write(tmpdir / "patches/a.patch", "--- a/index.js\n+++ b/index.js\n@@ -1,1 +1,1 @@\n-nope\n+deux\n")
        config = Core::Config.new.copy_with(prefix: tmpdir.to_s, store_path: (tmpdir / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true)
        expect_raises(Exception, /context mismatch/) do
          Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)
        end
        # A failing patch does not mark the package as installed: a fixed
        # patch applies cleanly on the next run.
        File.write(tmpdir / "patches/a.patch", "--- a/index.js\n+++ b/index.js\n@@ -1,1 +1,1 @@\n-one\n+deux\n")
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)
        File.read(tmpdir / "node_modules/a/index.js").should eq("deux\n")
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end

  it "re-links a package when its patch changes, and only that package" do
    It.with_registry do |registry|
      registry.add("a", "1.0.0", It.pkg("a", "1.0.0"), {"index.js" => "one\n"})
      registry.add("b", "1.0.0", It.pkg("b", "1.0.0"), {"index.js" => "b\n"})

      tmpdir = Path.new(Dir.tempdir, "zap-it-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(tmpdir)
        File.write(tmpdir / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"a":"1.0.0","b":"1.0.0"},"zap":{"patched_dependencies":{"a@1.0.0":"patches/a.patch"}}}))
        File.write(tmpdir / ".npmrc", "registry=#{registry.base_url}/\n")
        Dir.mkdir_p(tmpdir / "patches")
        File.write(tmpdir / "patches/a.patch", "--- a/index.js\n+++ b/index.js\n@@ -1,1 +1,1 @@\n-one\n+deux\n")
        config = Core::Config.new.copy_with(prefix: tmpdir.to_s, store_path: (tmpdir / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)
        File.read(tmpdir / "node_modules/a/index.js").should eq("deux\n")
        b_mtime = File.info(tmpdir / "node_modules/b").modification_time

        # Edit the patch: the patched package is re-linked with the new
        # content, the unpatched one is left untouched (pnpm style).
        File.write(tmpdir / "patches/a.patch", "--- a/index.js\n+++ b/index.js\n@@ -1,1 +1,1 @@\n-one\n+trois\n")
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)
        File.read(tmpdir / "node_modules/a/index.js").should eq("trois\n")
        File.info(tmpdir / "node_modules/b").modification_time.should eq(b_mtime)
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end

  it "fails a frozen install when a patch changed since the lockfile update" do
    It.with_registry do |registry|
      registry.add("a", "1.0.0", It.pkg("a", "1.0.0"), {"index.js" => "one\n"})

      tmpdir = Path.new(Dir.tempdir, "zap-it-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(tmpdir)
        File.write(tmpdir / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"a":"1.0.0"},"zap":{"patched_dependencies":{"a@1.0.0":"patches/a.patch"}}}))
        File.write(tmpdir / ".npmrc", "registry=#{registry.base_url}/\n")
        Dir.mkdir_p(tmpdir / "patches")
        File.write(tmpdir / "patches/a.patch", "--- a/index.js\n+++ b/index.js\n@@ -1,1 +1,1 @@\n-one\n+deux\n")
        config = Core::Config.new.copy_with(prefix: tmpdir.to_s, store_path: (tmpdir / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)

        File.write(tmpdir / "patches/a.patch", "--- a/index.js\n+++ b/index.js\n@@ -1,1 +1,1 @@\n-one\n+trois\n")
        expect_raises(Exception, /patched dependencies have been modified/) do
          Commands::Install.run(config, ic.copy_with(frozen_lockfile: true), raise_on_failure: true, reporter: Reporter::Null.new)
        end
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end

  it "restores the pristine package when the patch is removed from the config" do
    It.with_registry do |registry|
      registry.add("a", "1.0.0", It.pkg("a", "1.0.0"), {"index.js" => "one\n"})

      tmpdir = Path.new(Dir.tempdir, "zap-it-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(tmpdir)
        File.write(tmpdir / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"a":"1.0.0"},"zap":{"patched_dependencies":{"a@1.0.0":"patches/a.patch"}}}))
        File.write(tmpdir / ".npmrc", "registry=#{registry.base_url}/\n")
        Dir.mkdir_p(tmpdir / "patches")
        File.write(tmpdir / "patches/a.patch", "--- a/index.js\n+++ b/index.js\n@@ -1,1 +1,1 @@\n-one\n+deux\n")
        config = Core::Config.new.copy_with(prefix: tmpdir.to_s, store_path: (tmpdir / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)
        File.read(tmpdir / "node_modules/a/index.js").should eq("deux\n")

        File.write(tmpdir / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"a":"1.0.0"}}))
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)
        File.read(tmpdir / "node_modules/a/index.js").should eq("one\n")
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end

  it "keeps isolated packages installed on a no-op install" do
    It.with_registry do |registry|
      registry.add("a", "1.0.0", It.pkg("a", "1.0.0"), {"index.js" => "a\n"})

      tmpdir = Path.new(Dir.tempdir, "zap-it-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(tmpdir)
        File.write(tmpdir / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"a":"1.0.0"},"zap":{"strategy":"isolated"}}))
        File.write(tmpdir / ".npmrc", "registry=#{registry.base_url}/\n")
        config = Core::Config.new.copy_with(prefix: tmpdir.to_s, store_path: (tmpdir / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)
        package_dir = Path.new(Dir.glob((tmpdir / "node_modules/.store/*/node_modules/a").to_s).first)
        mtime = File.info(package_dir).modification_time

        # The state file makes the no-op install skip the linked packages
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)
        File.info(package_dir).modification_time.should eq(mtime)
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end

  it "seeds the state from legacy .zap.metadata markers on the first run" do
    It.with_registry do |registry|
      registry.add("a", "1.0.0", It.pkg("a", "1.0.0"), {"index.js" => "a\n"})

      tmpdir = Path.new(Dir.tempdir, "zap-it-#{Random::Secure.hex(4)}")
      begin
        # Simulate a pre-state install: the package dir with the legacy
        # marker, no state file
        Dir.mkdir_p(tmpdir / "node_modules/a")
        File.write(tmpdir / "node_modules/a/index.js", "a\n")
        File.write(tmpdir / "node_modules/a/.zap.metadata", "a@1.0.0")
        File.write(tmpdir / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"a":"1.0.0"}}))
        File.write(tmpdir / ".npmrc", "registry=#{registry.base_url}/\n")
        config = Core::Config.new.copy_with(prefix: tmpdir.to_s, store_path: (tmpdir / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true)
        mtime = File.info(tmpdir / "node_modules/a/index.js").modification_time

        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)

        # The seeded state matches: no re-link (the file is untouched, only
        # the marker inside the dir is deleted), marker removed, state saved
        File.info(tmpdir / "node_modules/a/index.js").modification_time.should eq(mtime)
        File.exists?(tmpdir / "node_modules/a/.zap.metadata").should be_false
        File.exists?(tmpdir / "node_modules/.zap-state").should be_true
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end

  it "passes a frozen install when no patches are configured" do
    It.with_registry do |registry|
      registry.add("a", "1.0.0", It.pkg("a", "1.0.0"), {"index.js" => "a\n"})

      tmpdir = Path.new(Dir.tempdir, "zap-it-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(tmpdir)
        File.write(tmpdir / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"a":"1.0.0"}}))
        File.write(tmpdir / ".npmrc", "registry=#{registry.base_url}/\n")
        config = Core::Config.new.copy_with(prefix: tmpdir.to_s, store_path: (tmpdir / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)

        # A lockfile without patched_dependencies (written above, or by a
        # pre-feature zap) must not look like a patch drift.
        Commands::Install.run(config, ic.copy_with(frozen_lockfile: true), raise_on_failure: true, reporter: Reporter::Null.new)
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end

  it "fails an install when a patch key matches no package" do
    It.with_registry do |registry|
      registry.add("a", "1.0.0", It.pkg("a", "1.0.0"), {"index.js" => "one\n"})

      tmpdir = Path.new(Dir.tempdir, "zap-it-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(tmpdir)
        File.write(tmpdir / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"a":"1.0.0"},"zap":{"patched_dependencies":{"a@1.0.0":"patches/a.patch","missing@1.0.0":"patches/missing.patch"}}}))
        File.write(tmpdir / ".npmrc", "registry=#{registry.base_url}/\n")
        Dir.mkdir_p(tmpdir / "patches")
        File.write(tmpdir / "patches/a.patch", "--- a/index.js\n+++ b/index.js\n@@ -1,1 +1,1 @@\n-one\n+deux\n")
        File.write(tmpdir / "patches/missing.patch", "--- a/index.js\n+++ b/index.js\n@@ -1,1 +1,1 @@\n-one\n+deux\n")
        config = Core::Config.new.copy_with(prefix: tmpdir.to_s, store_path: (tmpdir / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true)
        expect_raises(Exception, /did not match/) do
          Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)
        end
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end

  it "warns instead of failing when allow_unused_patches is set" do
    It.with_registry do |registry|
      registry.add("a", "1.0.0", It.pkg("a", "1.0.0"), {"index.js" => "one\n"})

      tmpdir = Path.new(Dir.tempdir, "zap-it-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(tmpdir)
        File.write(tmpdir / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"a":"1.0.0"},"zap":{"patched_dependencies":{"a@1.0.0":"patches/a.patch","missing@1.0.0":"patches/missing.patch"},"allow_unused_patches":true}}))
        File.write(tmpdir / ".npmrc", "registry=#{registry.base_url}/\n")
        Dir.mkdir_p(tmpdir / "patches")
        File.write(tmpdir / "patches/a.patch", "--- a/index.js\n+++ b/index.js\n@@ -1,1 +1,1 @@\n-one\n+deux\n")
        File.write(tmpdir / "patches/missing.patch", "--- a/index.js\n+++ b/index.js\n@@ -1,1 +1,1 @@\n-one\n+deux\n")
        config = Core::Config.new.copy_with(prefix: tmpdir.to_s, store_path: (tmpdir / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)
        File.read(tmpdir / "node_modules/a/index.js").should eq("deux\n")
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end

  it "applies a patch when install scripts are disabled" do
    It.with_registry do |registry|
      registry.add("a", "1.0.0", It.pkg("a", "1.0.0", scripts: {"postinstall" => "true"}), {"index.js" => "one\n"})

      tmpdir = Path.new(Dir.tempdir, "zap-it-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(tmpdir)
        File.write(tmpdir / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"a":"1.0.0"},"zap":{"patched_dependencies":{"a@1.0.0":"patches/a.patch"}}}))
        File.write(tmpdir / ".npmrc", "registry=#{registry.base_url}/\n")
        Dir.mkdir_p(tmpdir / "patches")
        File.write(tmpdir / "patches/a.patch", "--- a/index.js\n+++ b/index.js\n@@ -1,1 +1,1 @@\n-one\n+deux\n")
        config = Core::Config.new.copy_with(prefix: tmpdir.to_s, store_path: (tmpdir / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true, ignore_scripts: true)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)
        File.read(tmpdir / "node_modules/a/index.js").should eq("deux\n")
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end

  it "reports no changes on an unchanged patch-commit" do
    It.with_registry do |registry|
      registry.add("a", "1.0.0", It.pkg("a", "1.0.0"), {"index.js" => "one\n"})

      tmpdir = Path.new(Dir.tempdir, "zap-it-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(tmpdir)
        File.write(tmpdir / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"a":"1.0.0"}}))
        File.write(tmpdir / ".npmrc", "registry=#{registry.base_url}/\n")
        config = Core::Config.new.copy_with(prefix: tmpdir.to_s, store_path: (tmpdir / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)

        old_argv = ARGV.dup
        output = IO::Memory.new
        begin
          ARGV.replace(["a@1.0.0"])
          Commands::Patch.run(config, Commands::Patch::Config.new, output_io: output)
          patch_dir = Path.new(output.to_s.lines.find { |l| l.starts_with?("Patched package directory: ") }.not_nil!.split(": ", 2)[1].strip)
          ARGV.replace([patch_dir.to_s])
          Commands::Patch.run(config, Commands::Patch::Config.new.copy_with(commit: true), output_io: output)
          output.to_s.should contain("No changes were found.")
          File.exists?(tmpdir / "patches").should be_false
        ensure
          ARGV.replace(old_argv)
        end
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end

  it "writes an apply-to-all key for a bare-name patch" do
    It.with_registry do |registry|
      registry.add("a", "1.0.0", It.pkg("a", "1.0.0"), {"index.js" => "one\n"})

      tmpdir = Path.new(Dir.tempdir, "zap-it-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(tmpdir)
        File.write(tmpdir / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"a":"1.0.0"}}))
        File.write(tmpdir / ".npmrc", "registry=#{registry.base_url}/\n")
        config = Core::Config.new.copy_with(prefix: tmpdir.to_s, store_path: (tmpdir / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)

        old_argv = ARGV.dup
        output = IO::Memory.new
        begin
          ARGV.replace(["a"])
          Commands::Patch.run(config, Commands::Patch::Config.new, output_io: output)
          patch_dir = Path.new(output.to_s.lines.find { |l| l.starts_with?("Patched package directory: ") }.not_nil!.split(": ", 2)[1].strip)
          File.write(patch_dir / "index.js", "deux\n")
          ARGV.replace([patch_dir.to_s])
          Commands::Patch.run(config, Commands::Patch::Config.new.copy_with(commit: true), output_io: output)

          # The bare name is registered (apply-to-all), not name@version
          pkg_json = JSON.parse(File.read(tmpdir / "package.json"))
          pkg_json["zap"]["patched_dependencies"]["a"].should eq("patches/a.patch")
          File.exists?(tmpdir / "patches/a.patch").should be_true
        ensure
          ARGV.replace(old_argv)
        end
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end

  it "fails a bare-name patch when multiple versions are installed" do
    It.with_registry do |registry|
      registry.add("a", "1.0.0", It.pkg("a", "1.0.0"), {"index.js" => "one\n"})
      registry.add("a", "2.0.0", It.pkg("a", "2.0.0"), {"index.js" => "two\n"})
      registry.add("b", "1.0.0", It.pkg("b", "1.0.0", dependencies: {"a" => "^1.0.0"}), {"index.js" => "b\n"})
      registry.add("c", "1.0.0", It.pkg("c", "1.0.0", dependencies: {"a" => "^2.0.0"}), {"index.js" => "c\n"})

      tmpdir = Path.new(Dir.tempdir, "zap-it-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(tmpdir)
        File.write(tmpdir / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"b":"1.0.0","c":"1.0.0"}}))
        File.write(tmpdir / ".npmrc", "registry=#{registry.base_url}/\n")
        config = Core::Config.new.copy_with(prefix: tmpdir.to_s, store_path: (tmpdir / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)

        old_argv = ARGV.dup
        begin
          ARGV.replace(["a"])
          expect_raises(Exception, /multiple versions/i) do
            Commands::Patch.run(config, Commands::Patch::Config.new, output_io: IO::Memory.new)
          end
        ensure
          ARGV.replace(old_argv)
        end
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end

  it "replaces the patch when patch-commit runs again" do
    It.with_registry do |registry|
      registry.add("a", "1.0.0", It.pkg("a", "1.0.0"), {"index.js" => "one\n"})

      tmpdir = Path.new(Dir.tempdir, "zap-it-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(tmpdir)
        File.write(tmpdir / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"a":"1.0.0"}}))
        File.write(tmpdir / ".npmrc", "registry=#{registry.base_url}/\n")
        config = Core::Config.new.copy_with(prefix: tmpdir.to_s, store_path: (tmpdir / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)

        old_argv = ARGV.dup
        output = IO::Memory.new
        begin
          2.times do |i|
            ARGV.replace(["a@1.0.0"])
            Commands::Patch.run(config, Commands::Patch::Config.new, output_io: output)
            patch_dir = Path.new(output.to_s.lines.find { |l| l.starts_with?("Patched package directory: ") }.not_nil!.split(": ", 2)[1].strip)
            File.write(patch_dir / "index.js", "edit#{i}\n")
            ARGV.replace([patch_dir.to_s])
            Commands::Patch.run(config, Commands::Patch::Config.new.copy_with(commit: true), output_io: output)
          end

          pkg_json = JSON.parse(File.read(tmpdir / "package.json"))
          pkg_json["zap"]["patched_dependencies"].as_h.size.should eq(1)
          File.read(tmpdir / "patches/a@1.0.0.patch").should contain("edit1")
        ensure
          ARGV.replace(old_argv)
        end
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end

  it "fails patch-commit on a directory without the marker" do
    It.with_registry do |registry|
      registry.add("a", "1.0.0", It.pkg("a", "1.0.0"), {"index.js" => "one\n"})

      tmpdir = Path.new(Dir.tempdir, "zap-it-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(tmpdir)
        File.write(tmpdir / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"a":"1.0.0"}}))
        File.write(tmpdir / ".npmrc", "registry=#{registry.base_url}/\n")
        config = Core::Config.new.copy_with(prefix: tmpdir.to_s, store_path: (tmpdir / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)

        old_argv = ARGV.dup
        begin
          ARGV.replace([(tmpdir / "not-a-patch-dir").to_s])
          expect_raises(Exception, /not a zap patch directory/i) do
            Commands::Patch.run(config, Commands::Patch::Config.new.copy_with(commit: true), output_io: IO::Memory.new)
          end
        ensure
          ARGV.replace(old_argv)
        end
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end

  it "refuses to write a patch through a symlink" do
    It.with_registry do |registry|
      registry.add("a", "1.0.0", It.pkg("a", "1.0.0"), {"index.js" => "one\n"})

      tmpdir = Path.new(Dir.tempdir, "zap-it-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(tmpdir)
        File.write(tmpdir / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"a":"1.0.0"}}))
        File.write(tmpdir / ".npmrc", "registry=#{registry.base_url}/\n")
        config = Core::Config.new.copy_with(prefix: tmpdir.to_s, store_path: (tmpdir / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)

        old_argv = ARGV.dup
        output = IO::Memory.new
        begin
          ARGV.replace(["a@1.0.0"])
          Commands::Patch.run(config, Commands::Patch::Config.new, output_io: output)
          patch_dir = Path.new(output.to_s.lines.find { |l| l.starts_with?("Patched package directory: ") }.not_nil!.split(": ", 2)[1].strip)
          File.write(patch_dir / "index.js", "deux\n")

          # A patch file symlinked outside the patches dir must be refused
          Dir.mkdir_p(tmpdir / "patches")
          File.write(tmpdir / "outside.patch", "outside original\n")
          File.symlink(tmpdir / "outside.patch", tmpdir / "patches/a@1.0.0.patch")

          ARGV.replace([patch_dir.to_s])
          expect_raises(Exception, /must not be a symlink/i) do
            Commands::Patch.run(config, Commands::Patch::Config.new.copy_with(commit: true), output_io: output)
          end
          File.read(tmpdir / "outside.patch").should eq("outside original\n")
        ensure
          ARGV.replace(old_argv)
        end
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end

  it "accumulates on the existing patch with --update" do
    It.with_registry do |registry|
      registry.add("a", "1.0.0", It.pkg("a", "1.0.0"), {"index.js" => "one\n"})

      tmpdir = Path.new(Dir.tempdir, "zap-it-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(tmpdir)
        File.write(tmpdir / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"a":"1.0.0"}}))
        File.write(tmpdir / ".npmrc", "registry=#{registry.base_url}/\n")
        config = Core::Config.new.copy_with(prefix: tmpdir.to_s, store_path: (tmpdir / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)

        old_argv = ARGV.dup
        output = IO::Memory.new
        begin
          ARGV.replace(["a@1.0.0"])
          Commands::Patch.run(config, Commands::Patch::Config.new, output_io: output)
          dir1 = Path.new(output.to_s.lines.find { |l| l.starts_with?("Patched package directory: ") }.not_nil!.split(": ", 2)[1].strip)
          File.write(dir1 / "index.js", "v1\n")
          ARGV.replace([dir1.to_s])
          Commands::Patch.run(config, Commands::Patch::Config.new.copy_with(commit: true), output_io: output)

          # The update extraction starts from the already-patched content
          ARGV.replace(["a@1.0.0"])
          Commands::Patch.run(config, Commands::Patch::Config.new.copy_with(update: true), output_io: output)
          dir2 = Path.new(output.to_s.lines.select { |l| l.starts_with?("Patched package directory: ") }.last.split(": ", 2)[1].strip)
          File.read(dir2 / "index.js").should eq("v1\n")
          File.write(dir2 / "index.js", "v2\n")
          ARGV.replace([dir2.to_s])
          Commands::Patch.run(config, Commands::Patch::Config.new.copy_with(commit: true), output_io: output)

          # The accumulated patch is applied
          File.read(tmpdir / "node_modules/a/index.js").should eq("v2\n")
        ensure
          ARGV.replace(old_argv)
        end
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end

  it "restarts from the pristine copy by default" do
    It.with_registry do |registry|
      registry.add("a", "1.0.0", It.pkg("a", "1.0.0"), {"index.js" => "one\n"})

      tmpdir = Path.new(Dir.tempdir, "zap-it-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(tmpdir)
        File.write(tmpdir / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"a":"1.0.0"}}))
        File.write(tmpdir / ".npmrc", "registry=#{registry.base_url}/\n")
        config = Core::Config.new.copy_with(prefix: tmpdir.to_s, store_path: (tmpdir / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)

        old_argv = ARGV.dup
        output = IO::Memory.new
        begin
          ARGV.replace(["a@1.0.0"])
          Commands::Patch.run(config, Commands::Patch::Config.new, output_io: output)
          dir1 = Path.new(output.to_s.lines.find { |l| l.starts_with?("Patched package directory: ") }.not_nil!.split(": ", 2)[1].strip)
          File.write(dir1 / "index.js", "v1\n")
          ARGV.replace([dir1.to_s])
          Commands::Patch.run(config, Commands::Patch::Config.new.copy_with(commit: true), output_io: output)

          # A second default patch restarts from the pristine (yarn's default,
          # pnpm's --ignore-existing), not the patched copy
          ARGV.replace(["a@1.0.0"])
          Commands::Patch.run(config, Commands::Patch::Config.new, output_io: output)
          dir2 = Path.new(output.to_s.lines.select { |l| l.starts_with?("Patched package directory: ") }.last.split(": ", 2)[1].strip)
          File.read(dir2 / "index.js").should eq("one\n")
        ensure
          ARGV.replace(old_argv)
        end
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end

  it "extracts the pristine copy with --update when there is no existing patch" do
    It.with_registry do |registry|
      registry.add("a", "1.0.0", It.pkg("a", "1.0.0"), {"index.js" => "one\n"})

      tmpdir = Path.new(Dir.tempdir, "zap-it-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(tmpdir)
        File.write(tmpdir / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"a":"1.0.0"}}))
        File.write(tmpdir / ".npmrc", "registry=#{registry.base_url}/\n")
        config = Core::Config.new.copy_with(prefix: tmpdir.to_s, store_path: (tmpdir / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)

        old_argv = ARGV.dup
        output = IO::Memory.new
        begin
          ARGV.replace(["a@1.0.0"])
          Commands::Patch.run(config, Commands::Patch::Config.new.copy_with(update: true), output_io: output)
          dir = Path.new(output.to_s.lines.find { |l| l.starts_with?("Patched package directory: ") }.not_nil!.split(": ", 2)[1].strip)
          File.read(dir / "index.js").should eq("one\n")
        ensure
          ARGV.replace(old_argv)
        end
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end
end

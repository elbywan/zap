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
end

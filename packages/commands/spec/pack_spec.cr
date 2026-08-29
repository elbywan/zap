require "spec"
require "file_utils"
require "compress/gzip"
require "digest"
require "core/config"
require "reporter/null"
require "../install"
require "../pack"

# The install entry point prints the banner through the Zap module of the
# cli shard, which is not part of this shard: stub it like the integration
# helper does.
module Zap
  def self.print_banner; end
end

# Reads back a packed archive: raw entry names, modes and contents.
private def read_archive(path : Path) : Array(NamedTuple(name: String, mode: Int64, content: String))
  entries = [] of NamedTuple(name: String, mode: Int64, content: String)
  Compress::Gzip::Reader.open(File.new(path)) do |gzip|
    Crystar::Reader.open(gzip) do |tar|
      tar.each_entry do |entry|
        entries << {name: entry.name, mode: entry.mode, content: entry.io.gets_to_end}
      end
    end
  end
  entries
end

private def pack_fixture(dir : Path, manifest : String, files : Hash(String, String)) : Path
  Utils::Directories.mkdir_p(dir)
  File.write(dir / "package.json", manifest)
  files.each do |rel, content|
    full = dir / rel
    Utils::Directories.mkdir_p(full.dirname)
    File.write(full, content)
  end
  Commands::Pack.run(
    Core::Config.new.copy_with(prefix: dir.to_s, silent: true),
    Commands::Pack::Config.new,
    raise_on_failure: true,
  )
  dir / Commands::Pack::DEFAULT_ARCHIVE
end

describe Commands::Pack do
  it "packs a package into a deterministic self-contained tarball" do
    dir = Path.new(Dir.tempdir, "zap-pack-#{Random::Secure.hex(4)}")
    begin
      Dir.mkdir_p(dir / "lib")
      archive = pack_fixture(
        dir,
        %({"name":"demo","version":"1.2.3","main":"index.js"}),
        {"index.js" => "module.exports = 1\n", "lib/util.js" => "util\n"}
      )
      File.exists?(archive).should be_true

      entries = read_archive(archive)
      entries.map(&.[:name]).should eq([
        "package/index.js",
        "package/lib/util.js",
        "package/package.json",
      ])
      # The directory itself is not an entry (yarn parity)
      entries.map(&.[:name]).should_not contain("package/lib")
      entries.find(&.[:name].==("package/index.js")).not_nil![:content].should eq("module.exports = 1\n")
      entries.each do |entry|
        entry[:mode].should eq(0o644)
      end

      # Deterministic: a second pack is byte-identical
      File.write(dir / "package.json", %({"name":"demo","version":"1.2.3","main":"index.js"}))
      Commands::Pack.run(
        Core::Config.new.copy_with(prefix: dir.to_s, silent: true),
        Commands::Pack::Config.new,
        raise_on_failure: true,
      )
      first_bytes = File.read(archive)
      Commands::Pack.run(
        Core::Config.new.copy_with(prefix: dir.to_s, silent: true),
        Commands::Pack::Config.new,
        raise_on_failure: true,
      )
      File.read(archive).should eq(first_bytes)
      Digest::SHA256.hexdigest(File.read(archive)).should eq(Digest::SHA256.hexdigest(first_bytes))
    ensure
      FileUtils.rm_rf(dir)
    end
  end

  it "honors the files whitelist and always includes the essential files" do
    dir = Path.new(Dir.tempdir, "zap-pack-#{Random::Secure.hex(4)}")
    begin
      Dir.mkdir_p(dir / "lib")
      archive = pack_fixture(
        dir,
        %({"name":"demo","version":"1.0.0","files":["lib"]}),
        {"index.js" => "index\n", "lib/a.js" => "a\n", "README.md" => "readme\n"}
      )
      names = read_archive(archive).map(&.[:name])
      names.should contain("package/lib/a.js")
      names.should contain("package/README.md")
      names.should contain("package/package.json")
      names.should_not contain("package/index.js")
    ensure
      FileUtils.rm_rf(dir)
    end
  end

  it "includes main and bin even when outside the files whitelist" do
    dir = Path.new(Dir.tempdir, "zap-pack-#{Random::Secure.hex(4)}")
    begin
      Dir.mkdir_p(dir / "lib")
      archive = pack_fixture(
        dir,
        %({"name":"demo","version":"1.0.0","files":["lib"],"main":"index.js","bin":{"demo":"./bin/cli.js"}}),
        {"index.js" => "index\n", "lib/a.js" => "a\n", "bin/cli.js" => "cli\n"}
      )
      names = read_archive(archive).map(&.[:name])
      names.should contain("package/index.js")
      names.should contain("package/bin/cli.js")
      names.should_not contain("package/package-lock.json")
    ensure
      FileUtils.rm_rf(dir)
    end
  end

  it "makes bin entries executable and everything else 0644" do
    dir = Path.new(Dir.tempdir, "zap-pack-#{Random::Secure.hex(4)}")
    begin
      Dir.mkdir_p(dir / "bin")
      archive = pack_fixture(
        dir,
        %({"name":"demo","version":"1.0.0","bin":{"demo":"./bin/cli.js","other":"bin/other.js"}}),
        {"bin/cli.js" => "cli\n", "bin/other.js" => "other\n", "lib.js" => "lib\n"}
      )
      entries = read_archive(archive)
      entries.find(&.[:name].==("package/bin/cli.js")).not_nil![:mode].should eq(0o755)
      entries.find(&.[:name].==("package/bin/other.js")).not_nil![:mode].should eq(0o755)
      entries.find(&.[:name].==("package/lib.js")).not_nil![:mode].should eq(0o644)
    ensure
      FileUtils.rm_rf(dir)
    end
  end

  it "prefers .npmignore over .gitignore for exclusions" do
    dir = Path.new(Dir.tempdir, "zap-pack-#{Random::Secure.hex(4)}")
    begin
      archive = pack_fixture(
        dir,
        %({"name":"demo","version":"1.0.0"}),
        {"a.js" => "a\n", "b.js" => "b\n"}
      )
      File.write(dir / ".npmignore", "a.js\n")
      File.write(dir / ".gitignore", "b.js\n")
      # Re-run with the ignore files in place
      Commands::Pack.run(
        Core::Config.new.copy_with(prefix: dir.to_s, silent: true),
        Commands::Pack::Config.new,
        raise_on_failure: true,
      )
      names = read_archive(archive).map(&.[:name])
      names.should contain("package/b.js")
      names.should_not contain("package/a.js")
      # The ignore files themselves are not packed (npm / yarn parity)
      names.should_not contain("package/.npmignore")
      names.should_not contain("package/.gitignore")
    ensure
      FileUtils.rm_rf(dir)
    end
  end

  it "falls back to .gitignore when there is no .npmignore" do
    dir = Path.new(Dir.tempdir, "zap-pack-#{Random::Secure.hex(4)}")
    begin
      archive = pack_fixture(
        dir,
        %({"name":"demo","version":"1.0.0"}),
        {"a.js" => "a\n", "b.js" => "b\n"}
      )
      File.write(dir / ".gitignore", "a.js\n")
      Commands::Pack.run(
        Core::Config.new.copy_with(prefix: dir.to_s, silent: true),
        Commands::Pack::Config.new,
        raise_on_failure: true,
      )
      names = read_archive(archive).map(&.[:name])
      names.should contain("package/b.js")
      names.should_not contain("package/a.js")
    ensure
      FileUtils.rm_rf(dir)
    end
  end

  it "always excludes node_modules and .git" do
    dir = Path.new(Dir.tempdir, "zap-pack-#{Random::Secure.hex(4)}")
    begin
      Dir.mkdir_p(dir / "node_modules/dep")
      Dir.mkdir_p(dir / ".git")
      archive = pack_fixture(
        dir,
        %({"name":"demo","version":"1.0.0"}),
        {"index.js" => "index\n", "node_modules/dep/x.js" => "x\n", ".git/config" => "cfg\n"}
      )
      names = read_archive(archive).map(&.[:name])
      names.should contain("package/index.js")
      names.should_not contain("package/node_modules/dep/x.js")
      names.should_not contain("package/.git/config")
    ensure
      FileUtils.rm_rf(dir)
    end
  end

  it "follows file symlinks and skips dangling ones" do
    dir = Path.new(Dir.tempdir, "zap-pack-#{Random::Secure.hex(4)}")
    begin
      archive = pack_fixture(
        dir,
        %({"name":"demo","version":"1.0.0"}),
        {"real.js" => "real\n"}
      )
      File.symlink("real.js", dir / "link.js")
      File.symlink("missing.js", dir / "dangling.js")
      Commands::Pack.run(
        Core::Config.new.copy_with(prefix: dir.to_s, silent: true),
        Commands::Pack::Config.new,
        raise_on_failure: true,
      )
      entries = read_archive(archive)
      # The link is packed as its target content, not as a link entry
      entries.find(&.[:name].==("package/link.js")).not_nil![:content].should eq("real\n")
      entries.map(&.[:name]).should_not contain("package/dangling.js")
    ensure
      FileUtils.rm_rf(dir)
    end
  end

  it "follows a symlinked directory once and terminates on link cycles" do
    dir = Path.new(Dir.tempdir, "zap-pack-#{Random::Secure.hex(4)}")
    begin
      archive = pack_fixture(
        dir,
        %({"name":"demo","version":"1.0.0"}),
        {"root.js" => "root\n", "top/other.js" => "other\n"}
      )
      # sub -> . : a cycle back into the package root, cycle -> sub -> . :
      # a longer chain resolving back into the package.
      FileUtils.rm_rf(dir / "sub")
      File.symlink(".", dir / "sub")
      File.symlink("sub", dir / "cycle")
      Commands::Pack.run(
        Core::Config.new.copy_with(prefix: dir.to_s, silent: true),
        Commands::Pack::Config.new,
        raise_on_failure: true,
      )
      names = read_archive(archive).map(&.[:name])
      # Both sibling links resolve into the root and carry its content
      # once each; the cycles back into an ancestor are not followed.
      names.count(&.==("package/sub/root.js")).should eq(1)
      names.count(&.==("package/cycle/root.js")).should eq(1)
      names.should contain("package/sub/top/other.js")
      names.should_not contain("package/sub/cycle/root.js")
      names.should_not contain("package/cycle/sub/root.js")
    ensure
      FileUtils.rm_rf(dir)
    end
  end

  it "defaults the output name to package.tgz" do
    dir = Path.new(Dir.tempdir, "zap-pack-#{Random::Secure.hex(4)}")
    begin
      Dir.mkdir_p(dir)
      archive = pack_fixture(dir, %({"name":"demo","version":"1.0.0"}), {"index.js" => "index\n"})
      archive.should eq(dir / "package.tgz")
    ensure
      FileUtils.rm_rf(dir)
    end
  end

  it "interpolates %s and %v in the --out path and writes to the cwd" do
    dir = Path.new(Dir.tempdir, "zap-pack-#{Random::Secure.hex(4)}")
    outdir = Path.new(Dir.tempdir, "zap-pack-out-#{Random::Secure.hex(4)}")
    begin
      Dir.mkdir_p(dir)
      Dir.mkdir_p(outdir)
      File.write(dir / "package.json", %({"name":"@scope/demo","version":"2.0.0"}))
      File.write(dir / "index.js", "index\n")
      Commands::Pack.run(
        Core::Config.new.copy_with(prefix: dir.to_s, silent: true),
        Commands::Pack::Config.new(output: (outdir / "%s-%v.tgz").to_s),
        raise_on_failure: true,
      )
      # The scoped name is slugified (yarn parity)
      File.exists?(outdir / "scope-demo-2.0.0.tgz").should be_true
    ensure
      FileUtils.rm_rf(dir)
      FileUtils.rm_rf(outdir)
    end
  end

  it "defaults a missing version to 0.0.0" do
    dir = Path.new(Dir.tempdir, "zap-pack-#{Random::Secure.hex(4)}")
    outdir = Path.new(Dir.tempdir, "zap-pack-out-#{Random::Secure.hex(4)}")
    begin
      Dir.mkdir_p(dir)
      Dir.mkdir_p(outdir)
      File.write(dir / "package.json", %({"name":"demo"}))
      Commands::Pack.run(
        Core::Config.new.copy_with(prefix: dir.to_s, silent: true),
        Commands::Pack::Config.new(output: (outdir / "%s-%v.tgz").to_s),
        raise_on_failure: true,
      )
      File.exists?(outdir / "demo-0.0.0.tgz").should be_true
    ensure
      FileUtils.rm_rf(dir)
      FileUtils.rm_rf(outdir)
    end
  end

  it "packs a path argument instead of the prefix" do
    dir = Path.new(Dir.tempdir, "zap-pack-#{Random::Secure.hex(4)}")
    other = Path.new(Dir.tempdir, "zap-pack-other-#{Random::Secure.hex(4)}")
    begin
      Dir.mkdir_p(dir)
      Dir.mkdir_p(other)
      File.write(other / "package.json", %({"name":"other","version":"1.0.0"}))
      File.write(other / "index.js", "other\n")
      Commands::Pack.run(
        Core::Config.new.copy_with(prefix: dir.to_s, silent: true),
        Commands::Pack::Config.new(path: other.to_s),
        raise_on_failure: true,
      )
      File.exists?(other / "package.tgz").should be_true
      File.exists?(dir / "package.tgz").should be_false
    ensure
      FileUtils.rm_rf(dir)
      FileUtils.rm_rf(other)
    end
  end

  it "raises a clear error when package.json is missing" do
    dir = Path.new(Dir.tempdir, "zap-pack-#{Random::Secure.hex(4)}")
    begin
      Dir.mkdir_p(dir)
      expect_raises(Exception, /no package.json found/) do
        Commands::Pack.run(
          Core::Config.new.copy_with(prefix: dir.to_s, silent: true),
          Commands::Pack::Config.new,
          raise_on_failure: true,
        )
      end
    ensure
      FileUtils.rm_rf(dir)
    end
  end

  it "raises a clear error when the name is missing" do
    dir = Path.new(Dir.tempdir, "zap-pack-#{Random::Secure.hex(4)}")
    begin
      Dir.mkdir_p(dir)
      File.write(dir / "package.json", %({"version":"1.0.0"}))
      expect_raises(Exception, /missing "name"/) do
        Commands::Pack.run(
          Core::Config.new.copy_with(prefix: dir.to_s, silent: true),
          Commands::Pack::Config.new,
          raise_on_failure: true,
        )
      end
    ensure
      FileUtils.rm_rf(dir)
    end
  end

  it "produces an archive installable by zap through a file: dependency" do
    dir = Path.new(Dir.tempdir, "zap-pack-#{Random::Secure.hex(4)}")
    project = Path.new(Dir.tempdir, "zap-pack-install-#{Random::Secure.hex(4)}")
    begin
      Dir.mkdir_p(dir)
      Dir.mkdir_p(project)
      pack_fixture(
        dir,
        %({"name":"packed-dep","version":"3.1.4","main":"index.js","bin":{"packed-dep":"cli.js"}}),
        {"index.js" => "module.exports = 42\n", "cli.js" => "#!/usr/bin/env node\nconsole.log(42)\n"}
      )
      File.write(project / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"packed-dep":"file:./packed-dep.tgz"}}))
      FileUtils.cp(dir / "package.tgz", project / "packed-dep.tgz")
      Commands::Install.run(
        Core::Config.new.copy_with(prefix: project.to_s, store_path: (project / "store").to_s, silent: true),
        Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: false),
        raise_on_failure: true,
        reporter: Reporter::Null.new,
      )
      JSON.parse(File.read(project / "node_modules/packed-dep/package.json"))["version"].as_s.should eq("3.1.4")
      File.read(project / "node_modules/packed-dep/index.js").should eq("module.exports = 42\n")
      # The bin is linked
      File.symlink?(project / "node_modules/.bin/packed-dep").should be_true
    ensure
      FileUtils.rm_rf(dir)
      FileUtils.rm_rf(project)
    end
  end

  it "packs a workspace member directory" do
    root = Path.new(Dir.tempdir, "zap-pack-ws-#{Random::Secure.hex(4)}")
    member = root / "packages" / "member"
    begin
      Dir.mkdir_p(member / "src")
      File.write(root / "package.json", %({"name":"ws-root","version":"1.0.0","workspaces":["packages/*"]}))
      File.write(member / "package.json", %({"name":"@ws/member","version":"0.5.0","main":"src/index.js"}))
      File.write(member / "src/index.js", "member\n")
      Commands::Pack.run(
        Core::Config.new.copy_with(prefix: root.to_s, silent: true),
        Commands::Pack::Config.new(path: member.to_s),
        raise_on_failure: true,
      )
      entries = read_archive(member / "package.tgz").map(&.[:name])
      entries.should contain("package/src/index.js")
      entries.should contain("package/package.json")
    ensure
      FileUtils.rm_rf(root)
    end
  end

  it "packs a large tree deterministically" do
    dir = Path.new(Dir.tempdir, "zap-pack-big-#{Random::Secure.hex(4)}")
    begin
      Dir.mkdir_p(dir)
      files = {} of String => String
      300.times do |i|
        files["src/mod#{i / 10}/file#{i}.js"] = "content #{i}\n"
      end
      archive = pack_fixture(dir, %({"name":"big","version":"1.0.0"}), files)
      entries = read_archive(archive)
      entries.size.should eq(301) # 300 files + package.json
      entries.map(&.[:name]).should eq(entries.map(&.[:name]).sort)
      first = File.read(archive)
      Commands::Pack.run(
        Core::Config.new.copy_with(prefix: dir.to_s, silent: true),
        Commands::Pack::Config.new,
        raise_on_failure: true,
      )
      File.read(archive).should eq(first)
    ensure
      FileUtils.rm_rf(dir)
    end
  end
end

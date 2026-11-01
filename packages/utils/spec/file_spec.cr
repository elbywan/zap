require "spec"
require "file_utils"
require "../file"

describe Utils::File do
  describe ".safe_join" do
    it "keeps legitimate package names under the base directory" do
      Utils::File.safe_join("/tmp/node_modules", "@scope/pkg").to_s.should eq("/tmp/node_modules/@scope/pkg")
      Utils::File.safe_join("/tmp/node_modules", "pkg").to_s.should eq("/tmp/node_modules/pkg")
    end

    it "normalizes harmless dot components" do
      Utils::File.safe_join("/tmp/node_modules", "pkg/../other").to_s.should eq("/tmp/node_modules/other")
    end

    it "rejects a parent symlink that escapes the base" do
      dir = Path.new(Dir.tempdir, "zap-safe-join-#{Random::Secure.hex(4)}")
      base = dir / "node_modules"
      outside = dir / "outside"
      begin
        Dir.mkdir_p(base)
        Dir.mkdir_p(outside)
        File.symlink(outside, base / "@scope")
        expect_raises(Exception, /parent escapes/) do
          Utils::File.safe_join(base, "@scope/pkg")
        end
      ensure
        FileUtils.rm_rf(dir)
      end
    end

    it "rejects traversal and empty components" do
      expect_raises(Exception, /escapes/) do
        Utils::File.safe_join("/tmp/node_modules", "../escaped")
      end
      expect_raises(Exception, /empty/) do
        Utils::File.safe_join("/tmp/node_modules", "")
      end
    end
  end

  describe ".linkeable_ancestor?" do
    it "does not leave hardlink probe files behind" do
      dir = Path.new(Dir.tempdir, "zap-linkable-#{Random::Secure.hex(4)}")
      child = dir / "child"
      source = dir / "source"
      destination = dir / "destination"
      begin
        Dir.mkdir_p(child)
        Dir.mkdir_p(source)
        Dir.mkdir_p(destination)
        Utils::File.linkeable_ancestor?(child).should_not be_nil
        Utils::File.can_hardlink?(source, destination).should be_true
        Dir.children(dir).sort.should eq(["child", "destination", "source"])
        Dir.children(child).should be_empty
        Dir.children(source).should be_empty
        Dir.children(destination).should be_empty
      ensure
        FileUtils.rm_rf(dir)
      end
    end
  end

  describe ".bin_name" do
    it "strips both slash styles and rejects traversal names" do
      Utils::File.bin_name("bin/tool").should eq("tool")
      Utils::File.bin_name("bin\\tool").should eq("tool")
      Utils::File.bin_name("..").should be_nil
      Utils::File.bin_name("bin/..").should be_nil
      Utils::File.bin_name("..\\tool").should eq("tool")
      Utils::File.bin_name("C:tool").should be_nil
    end
  end

  describe ".safe_bin_path" do
    it "keeps relative bin paths inside the package" do
      Utils::File.safe_bin_path("/tmp/pkg", "bin/tool").to_s.should eq("/tmp/pkg/bin/tool")
      expect_raises(Exception, /relative/) { Utils::File.safe_bin_path("/tmp/pkg", "/bin/tool") }
      expect_raises(Exception, /escapes/) { Utils::File.safe_bin_path("/tmp/pkg", "../tool") }
      dir = Path.new(Dir.tempdir, "zap-bin-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(dir / "pkg")
        File.write(dir / "outside", "x")
        File.symlink(dir / "outside", dir / "pkg" / "tool")
        expect_raises(Exception, /escapes/) { Utils::File.safe_bin_path(dir / "pkg", "tool") }
      ensure
        FileUtils.rm_rf(dir)
      end
    end
  end

  describe ".atomic_write" do
    it "replaces a file completely and cleans up its temporary file" do
      dir = Path.new(Dir.tempdir, "zap-atomic-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(dir)
        path = dir / "data"
        File.write(path, "old")
        Utils::File.atomic_write(path, "new")
        File.read(path).should eq("new")
        Dir.children(dir).should eq(["data"])
      ensure
        FileUtils.rm_rf(dir)
      end
    end

    it "keeps a symlink and writes its dangling target" do
      dir = Path.new(Dir.tempdir, "zap-atomic-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(dir)
        target = dir / "target"
        link = dir / "link"
        File.symlink(target, link)
        Utils::File.atomic_write(link, "data")
        File.symlink?(link).should be_true
        File.read(target).should eq("data")
      ensure
        FileUtils.rm_rf(dir)
      end
    end

    it "replaces a symlink instead of writing through it when disabled" do
      dir = Path.new(Dir.tempdir, "zap-atomic-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(dir)
        target = dir / "outside"
        link = dir / "link"
        File.write(target, "old")
        File.symlink(target, link)
        Utils::File.atomic_write(link, "data", follow_symlinks: false)
        File.symlink?(link).should be_false
        File.read(target).should eq("old")
        File.read(link).should eq("data")
      ensure
        FileUtils.rm_rf(dir)
      end
    end

    it "keeps the previous file when the write fails" do
      dir = Path.new(Dir.tempdir, "zap-atomic-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(dir)
        path = dir / "data"
        File.write(path, "old")
        expect_raises(Exception, "boom") do
          Utils::File.atomic_write(path) do |io|
            io << "partial"
            raise "boom"
          end
        end
        File.read(path).should eq("old")
        Dir.children(dir).should eq(["data"])
      ensure
        FileUtils.rm_rf(dir)
      end
    end
  end
end

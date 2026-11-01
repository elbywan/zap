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

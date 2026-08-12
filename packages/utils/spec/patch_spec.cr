require "spec"
require "file_utils"
require "../patch"

describe Utils::Patch do
  it "applies a simple hunk" do
    dir = Path.new(Dir.tempdir, "zap-patch-#{Random::Secure.hex(4)}")
    begin
      Dir.mkdir_p(dir)
      File.write(dir / "a.txt", "one\ntwo\nthree\n")
      patch = "--- a/a.txt\n+++ b/a.txt\n@@ -1,3 +1,3 @@\n one\n-two\n+deux\n three\n"
      Utils::Patch.apply(patch, dir)
      File.read(dir / "a.txt").should eq("one\ndeux\nthree\n")
    ensure
      FileUtils.rm_rf(dir)
    end
  end

  it "creates and deletes files" do
    dir = Path.new(Dir.tempdir, "zap-patch-#{Random::Secure.hex(4)}")
    begin
      Dir.mkdir_p(dir)
      patch = "--- /dev/null\n+++ b/new.txt\n@@ -0,0 +1,2 @@\n+hello\n+world\n--- a/old.txt\n+++ /dev/null\n@@ -1,1 +0,0 @@\n-gone\n"
      File.write(dir / "old.txt", "gone\n")
      Utils::Patch.apply(patch, dir)
      File.read(dir / "new.txt").should eq("hello\nworld\n")
      File.exists?(dir / "old.txt").should be_false
    ensure
      FileUtils.rm_rf(dir)
    end
  end

  it "raises on a context mismatch" do
    dir = Path.new(Dir.tempdir, "zap-patch-#{Random::Secure.hex(4)}")
    begin
      Dir.mkdir_p(dir)
      File.write(dir / "a.txt", "one\ntwo\n")
      patch = "--- a/a.txt\n+++ b/a.txt\n@@ -1,2 +1,2 @@\n one\n-nope\n+yes\n"
      expect_raises(Exception, /context mismatch/) { Utils::Patch.apply(patch, dir) }
    ensure
      FileUtils.rm_rf(dir)
    end
  end

  it "preserves a missing trailing newline" do
    a = Path.new(Dir.tempdir, "zap-patch-#{Random::Secure.hex(4)}")
    b = Path.new(Dir.tempdir, "zap-patch-#{Random::Secure.hex(4)}")
    begin
      Dir.mkdir_p(a)
      Dir.mkdir_p(b)
      File.write(a / "f.txt", "one\ntwo") # no trailing newline
      File.write(b / "f.txt", "one\ntwo\nthree") # still none
      patch = Utils::Patch.generate(a, b)
      Utils::Patch.apply(patch, a)
      File.read(a / "f.txt").should eq("one\ntwo\nthree")
      File.read(a / "f.txt").ends_with?('\n').should be_false
    ensure
      FileUtils.rm_rf(a)
      FileUtils.rm_rf(b)
    end
  end

  it "round-trips a generated tree diff" do
    a = Path.new(Dir.tempdir, "zap-patch-#{Random::Secure.hex(4)}")
    b = Path.new(Dir.tempdir, "zap-patch-#{Random::Secure.hex(4)}")
    begin
      Dir.mkdir_p(a / "lib")
      Dir.mkdir_p(b / "lib")
      File.write(a / "index.js", "const x = 1;\nconsole.log(x);\n")
      File.write(b / "index.js", "const x = 42;\nconsole.log(x);\n// patched\n")
      File.write(a / "lib/keep.txt", "same\n")
      File.write(b / "lib/keep.txt", "same\n")
      File.write(a / "gone.js", "delete me\n")

      patch = Utils::Patch.generate(a, b)
      patch.should contain("index.js")
      patch.should contain("gone.js")
      patch.should_not contain("keep.txt")

      FileUtils.rm_rf(b)
      Utils::Directories.mkdir_p(b / "lib")
      File.write(b / "index.js", "const x = 1;\nconsole.log(x);\n")
      File.write(b / "lib/keep.txt", "same\n")
      File.write(b / "gone.js", "delete me\n")
      Utils::Patch.apply(patch, b)
      File.read(b / "index.js").should eq("const x = 42;\nconsole.log(x);\n// patched\n")
      File.exists?(b / "gone.js").should be_false
    ensure
      FileUtils.rm_rf(a)
      FileUtils.rm_rf(b)
    end
  end
end

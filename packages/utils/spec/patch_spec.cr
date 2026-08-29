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

  it "rejects a patch with no parseable sections" do
    dir = Path.new(Dir.tempdir, "zap-patch-#{Random::Secure.hex(4)}")
    begin
      Dir.mkdir_p(dir)
      expect_raises(Exception, /no changes found/) do
        Utils::Patch.apply("this is not a patch", dir)
      end
    ensure
      FileUtils.rm_rf(dir)
    end
  end

  it "rejects a hunk whose header counts do not match the body" do
    dir = Path.new(Dir.tempdir, "zap-patch-#{Random::Secure.hex(4)}")
    begin
      Dir.mkdir_p(dir)
      File.write(dir / "a.txt", "one\n")
      # The header claims 5 old lines, the body has 1
      patch = "--- a/a.txt\n+++ b/a.txt\n@@ -1,5 +1,4 @@\n one\n"
      expect_raises(Exception, /counts do not match/) { Utils::Patch.apply(patch, dir) }
    ensure
      FileUtils.rm_rf(dir)
    end
  end

  it "applies a CRLF patch to an LF file" do
    dir = Path.new(Dir.tempdir, "zap-patch-#{Random::Secure.hex(4)}")
    begin
      Dir.mkdir_p(dir)
      File.write(dir / "a.txt", "one\n")
      patch = "--- a/a.txt\r\n+++ b/a.txt\r\n@@ -1,1 +1,1 @@\r\n-one\r\n+two\r\n"
      Utils::Patch.apply(patch, dir)
      File.read(dir / "a.txt").should eq("two\n")
    ensure
      FileUtils.rm_rf(dir)
    end
  end

  it "tolerates a stray blank line between the header and the hunk" do
    dir = Path.new(Dir.tempdir, "zap-patch-#{Random::Secure.hex(4)}")
    begin
      Dir.mkdir_p(dir)
      File.write(dir / "a.txt", "one\n")
      patch = "--- a/a.txt\n+++ b/a.txt\n\n@@ -1,1 +1,1 @@\n-one\n+two\n"
      Utils::Patch.apply(patch, dir)
      File.read(dir / "a.txt").should eq("two\n")
    ensure
      FileUtils.rm_rf(dir)
    end
  end

  it "tolerates git diff headers" do
    dir = Path.new(Dir.tempdir, "zap-patch-#{Random::Secure.hex(4)}")
    begin
      Dir.mkdir_p(dir)
      File.write(dir / "a.txt", "one\n")
      patch = "diff --git a/a.txt b/a.txt\nindex 0000000..1111111 100644\n--- a/a.txt\n+++ b/a.txt\n@@ -1,1 +1,1 @@\n-one\n+two\n"
      Utils::Patch.apply(patch, dir)
      File.read(dir / "a.txt").should eq("two\n")
    ensure
      FileUtils.rm_rf(dir)
    end
  end

  it "applies a rename" do
    dir = Path.new(Dir.tempdir, "zap-patch-#{Random::Secure.hex(4)}")
    begin
      Dir.mkdir_p(dir)
      File.write(dir / "numbers.txt", "one\ntwo\n")
      patch = "diff --git a/numbers.txt b/banana.txt\nrename from numbers.txt\nrename to banana.txt\n--- a/numbers.txt\n+++ b/banana.txt\n@@ -1,2 +1,2 @@\n-one\n+uno\n two\n"
      Utils::Patch.apply(patch, dir)
      File.exists?(dir / "numbers.txt").should be_false
      File.read(dir / "banana.txt").should eq("uno\ntwo\n")
    ensure
      FileUtils.rm_rf(dir)
    end
  end

  it "leaves the content intact for a mode-only change" do
    dir = Path.new(Dir.tempdir, "zap-patch-#{Random::Secure.hex(4)}")
    begin
      Dir.mkdir_p(dir)
      File.write(dir / "a.txt", "unchanged\n")
      patch = "diff --git a/a.txt b/a.txt\nold mode 100644\nnew mode 100755\n--- a/a.txt\n+++ b/a.txt\n"
      Utils::Patch.apply(patch, dir)
      File.read(dir / "a.txt").should eq("unchanged\n")
    ensure
      FileUtils.rm_rf(dir)
    end
  end

  it "handles unicode directory names" do
    a = Path.new(Dir.tempdir, "zap-patch-#{Random::Secure.hex(4)}")
    b = Path.new(Dir.tempdir, "zap-patch-#{Random::Secure.hex(4)}")
    begin
      Dir.mkdir_p(a / "测试")
      Dir.mkdir_p(b / "测试")
      File.write(a / "测试/foo.txt", "one\n")
      File.write(b / "测试/foo.txt", "two\n")
      patch = Utils::Patch.generate(a, b)
      Utils::Patch.apply(patch, a)
      File.read(a / "测试/foo.txt").should eq("two\n")
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

  it "parses a removed line whose content starts with '-- '" do
    dir = Path.new(Dir.tempdir, "zap-patch-#{Random::Secure.hex(4)}")
    begin
      Dir.mkdir_p(dir)
      File.write(dir / "a.txt", "keep\n-- signature\nend\n")
      # The removed line yields the body line "--- signature", which must
      # not be mistaken for the next file-section header.
      patch = "--- a/a.txt\n+++ b/a.txt\n@@ -1,3 +1,2 @@\n keep\n--- signature\n end\n"
      Utils::Patch.apply(patch, dir)
      File.read(dir / "a.txt").should eq("keep\nend\n")
    ensure
      FileUtils.rm_rf(dir)
    end
  end

  it "parses an added line whose content starts with '++ '" do
    dir = Path.new(Dir.tempdir, "zap-patch-#{Random::Secure.hex(4)}")
    begin
      Dir.mkdir_p(dir)
      File.write(dir / "a.txt", "one\n")
      patch = "--- a/a.txt\n+++ b/a.txt\n@@ -1,1 +1,2 @@\n one\n+++ counter\n"
      Utils::Patch.apply(patch, dir)
      File.read(dir / "a.txt").should eq("one\n++ counter\n")
    ensure
      FileUtils.rm_rf(dir)
    end
  end

  it "writes the trailing newline when only the original lacked it" do
    dir = Path.new(Dir.tempdir, "zap-patch-#{Random::Secure.hex(4)}")
    begin
      Dir.mkdir_p(dir)
      File.write(dir / "a.txt", "foo") # no trailing newline
      # git diff of "foo" -> "foo\nbar\n": the marker follows the '-' line,
      # so only the original side lacks the newline.
      patch = "--- a/a.txt\n+++ b/a.txt\n@@ -1 +1,2 @@\n-foo\n\\ No newline at end of file\n+foo\n+bar\n"
      Utils::Patch.apply(patch, dir)
      File.read(dir / "a.txt").should eq("foo\nbar\n")
    ensure
      FileUtils.rm_rf(dir)
    end
  end

  it "drops the trailing newline when the modified file lacks it" do
    dir = Path.new(Dir.tempdir, "zap-patch-#{Random::Secure.hex(4)}")
    begin
      Dir.mkdir_p(dir)
      File.write(dir / "a.txt", "foo\nbar\n")
      patch = "--- a/a.txt\n+++ b/a.txt\n@@ -1,2 +1,2 @@\n foo\n-bar\n+bar\n\\ No newline at end of file\n"
      Utils::Patch.apply(patch, dir)
      File.read(dir / "a.txt").should eq("foo\nbar")
      File.read(dir / "a.txt").ends_with?('\n').should be_false
    ensure
      FileUtils.rm_rf(dir)
    end
  end
end

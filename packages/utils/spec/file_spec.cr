require "spec"
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
end

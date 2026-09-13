require "./spec_helper"
require "../../install/manifest"
require "../../install/packument_scanner"

module Commands::Install::Spec
  describe PackumentScanner do
    it "scans the fields and every version span round-trips through JSON.parse" do
      body = <<-JSON
        {"name":"x","dist-tags":{"latest":"1.0.1"},
         "versions":{"1.0.0":{"name":"x","version":"1.0.0","dependencies":{"a":"^1","b":">=2 <3"}},
                     "1.0.1":{"name":"x","version":"1.0.1","engines":{"node":">=14"}}},
         "time":{"1.0.0":"2020-01-01T00:00:00.000Z","1.0.1":"2020-02-01T00:00:00.000Z","modified":"2020-02-01T00:00:00.000Z"}}
        JSON
      scanned = PackumentScanner.scan(body).not_nil!
      scanned.versions.sort.should eq(["1.0.0", "1.0.1"])
      scanned.dist_tags.should eq({"latest" => "1.0.1"})
      scanned.times["1.0.1"].should eq("2020-02-01T00:00:00.000Z")
      scanned.version_spans.size.should eq(2)
      scanned.version_spans.each do |version, span|
        JSON.parse(body.byte_slice(span[0], span[1]))["version"].as_s.should eq(version)
      end
      # The manifest built from the scanner matches the pull parser's data.
      manifest = Manifest.new(body)
      manifest.versions.sort.should eq(["1.0.0", "1.0.1"])
      JSON.parse(manifest.get_raw_metadata?(Semver.parse("1.0.0")).not_nil!)["version"].as_s.should eq("1.0.0")
    end

    it "does not desync on brackets and escaped quotes inside strings" do
      body = <<-JSON
        {"description":"a { [ } ] \\" quote","dist-tags":{"latest":"1.0.0"},
         "versions":{"1.0.0":{"name":"x","version":"1.0.0","description":"{ nested \\"quotes\\" }","keywords":["a]b","c{d"]}},
         "time":{"1.0.0":"2020-01-01T00:00:00.000Z"}}
        JSON
      scanned = PackumentScanner.scan(body).not_nil!
      scanned.versions.should eq(["1.0.0"])
      span = scanned.version_spans["1.0.0"]
      parsed = JSON.parse(body.byte_slice(span[0], span[1]))
      parsed["version"].as_s.should eq("1.0.0")
      parsed["description"].as_s.should eq(%({ nested "quotes" }))
    end

    it "tolerates the minimal packument shape (no time, no dist-tags)" do
      body = %({"name":"x","versions":{"1.2.3":{"name":"x","version":"1.2.3"}}})
      scanned = PackumentScanner.scan(body).not_nil!
      scanned.versions.should eq(["1.2.3"])
      scanned.times.should be_empty
      scanned.dist_tags.should be_empty
    end

    it "returns nil (parser fallback) for malformed or unexpected input" do
      # Truncated mid-value.
      PackumentScanner.scan(%({"versions":{"1.0.0":)).should be_nil
      # Not an object.
      PackumentScanner.scan(%(["versions"])).should be_nil
      # Garbage after the versions object.
      PackumentScanner.scan(%({"versions":{"1.0.0":{}} "x"})).should be_nil
      # Unterminated string.
      PackumentScanner.scan(%({"versions":{"1.0.0":{"version":"1.0.0}})).should be_nil
    end
  end
end

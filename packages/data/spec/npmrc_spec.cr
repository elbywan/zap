require "spec"
require "file_utils"
require "../npmrc"

describe Data::Npmrc do
  it "expands ${VAR} without leaking a dollar sign" do
    dir = Path.new(Dir.tempdir, "zap-npmrc-#{Random::Secure.hex(4)}")
    begin
      Dir.mkdir_p(dir)
      ENV["ZAP_NPMRC_TEST_TOKEN"] = "secret123"
      File.write(dir / ".npmrc", "//zap-test-registry.invalid/:_authToken=${ZAP_NPMRC_TEST_TOKEN}\n")
      npmrc = Data::Npmrc.new(dir)
      npmrc.registries_auth["https://zap-test-registry.invalid/"].not_nil!.authToken.should eq("secret123")
    ensure
      ENV.delete("ZAP_NPMRC_TEST_TOKEN")
      FileUtils.rm_rf(dir)
    end
  end

  it "keeps a dollar sign that is not followed by a brace literal" do
    dir = Path.new(Dir.tempdir, "zap-npmrc-#{Random::Secure.hex(4)}")
    begin
      Dir.mkdir_p(dir)
      File.write(dir / ".npmrc", "//zap-test-registry.invalid/:_authToken=$LITERAL\n")
      npmrc = Data::Npmrc.new(dir)
      npmrc.registries_auth["https://zap-test-registry.invalid/"].not_nil!.authToken.should eq("$LITERAL")
    ensure
      FileUtils.rm_rf(dir)
    end
  end
end

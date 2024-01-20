require "spec"
require "./alias"

alias AliasProtocol = Zap::Commands::Install::Protocol::Alias

describe AliasProtocol, tags: "protocol" do
  {
    {"my-react@npm:react", {"npm:react", "my-react"}},
    {"my-react@alias:react", {"alias:react", "my-react"}},
    {"jquery2@npm:jquery@2", {"npm:jquery@2", "jquery2"}},
    {"jquery2@alias:jquery@2", {"alias:jquery@2", "jquery2"}},
    {"jquery-next@npm:jquery@next", {"npm:jquery@next", "jquery-next"}},
    {"jquery-next@alias:jquery@next", {"alias:jquery@next", "jquery-next"}},
    {"npa@npm:npm-package-arg", {"npm:npm-package-arg", "npa"}},
    {"npa@alias:npm-package-arg", {"alias:npm-package-arg", "npa"}},
  }.each do |(specifier, expected)|
    it "should normalize specifiers (#{specifier})" do
      AliasProtocol.normalize?(specifier, nil).should eq(expected)
    end
  end
end

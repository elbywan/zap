require "spec"
require "./workspace"

describe Zap::Commands::Install::Protocol::Workspace, tags: "protocol" do
  {
    {"whatever", nil},
  }.each do |(specifier, expected)|
    it "should normalize specifiers (#{specifier})" do
      Zap::Commands::Install::Protocol::Workspace.normalize?(specifier, nil).should eq(expected)
    end
  end
end

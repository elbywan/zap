require "spec"
require "./filter"

describe Zap::Utils::Filter do
  it "should parse filters" do
    filter = Zap::Utils::Filter.new "@babel/*"
    filter.scope.should eq "@babel/*"
    filter.glob.should be_nil
    filter.since.should be_nil
    filter.exclude.should be_false
    filter.include_dependencies.should be_false
    filter.include_dependents.should be_false
    filter.exclude_self.should be_false

    filter = Zap::Utils::Filter.new "foo..."
    filter.scope.should eq "foo"
    filter.glob.should be_nil
    filter.since.should be_nil
    filter.exclude.should be_false
    filter.include_dependencies.should be_true
    filter.include_dependents.should be_false
    filter.exclude_self.should be_false

    filter = Zap::Utils::Filter.new "@babel/preset-*..."
    filter.scope.should eq "@babel/preset-*"
    filter.glob.should be_nil
    filter.since.should be_nil
    filter.exclude.should be_false
    filter.include_dependencies.should be_true
    filter.include_dependents.should be_false
    filter.exclude_self.should be_false

    filter = Zap::Utils::Filter.new "foo^..."
    filter.scope.should eq "foo"
    filter.glob.should be_nil
    filter.since.should be_nil
    filter.exclude.should be_false
    filter.include_dependencies.should be_true
    filter.include_dependents.should be_false
    filter.exclude_self.should be_true

    filter = Zap::Utils::Filter.new "...foo"
    filter.scope.should eq "foo"
    filter.glob.should be_nil
    filter.since.should be_nil
    filter.exclude.should be_false
    filter.include_dependencies.should be_false
    filter.include_dependents.should be_true
    filter.exclude_self.should be_false

    filter = Zap::Utils::Filter.new "...^foo"
    filter.scope.should eq "foo"
    filter.glob.should be_nil
    filter.since.should be_nil
    filter.exclude.should be_false
    filter.include_dependencies.should be_false
    filter.include_dependents.should be_true
    filter.exclude_self.should be_true

    filter = Zap::Utils::Filter.new "./packages/**"
    filter.scope.should be_nil
    filter.glob.should eq "packages/**"
    filter.since.should be_nil
    filter.exclude.should be_false
    filter.include_dependencies.should be_false
    filter.include_dependents.should be_false
    filter.exclude_self.should be_false

    filter = Zap::Utils::Filter.new "...{<directory>}"
    filter.scope.should be_nil
    filter.glob.should eq "<directory>"
    filter.since.should be_nil
    filter.exclude.should be_false
    filter.include_dependencies.should be_false
    filter.include_dependents.should be_true
    filter.exclude_self.should be_false

    filter = Zap::Utils::Filter.new "{<directory>}..."
    filter.scope.should be_nil
    filter.glob.should eq "<directory>"
    filter.since.should be_nil
    filter.exclude.should be_false
    filter.include_dependencies.should be_true
    filter.include_dependents.should be_false
    filter.exclude_self.should be_false

    filter = Zap::Utils::Filter.new "...{<directory>}..."
    filter.scope.should be_nil
    filter.glob.should eq "<directory>"
    filter.since.should be_nil
    filter.exclude.should be_false
    filter.include_dependencies.should be_true
    filter.include_dependents.should be_true
    filter.exclude_self.should be_false

    filter = Zap::Utils::Filter.new "{packages/**}[origin/master]"
    filter.scope.should be_nil
    filter.glob.should eq "packages/**"
    filter.since.should eq "origin/master"
    filter.exclude.should be_false
    filter.include_dependencies.should be_false
    filter.include_dependents.should be_false
    filter.exclude_self.should be_false

    filter = Zap::Utils::Filter.new "...{packages/**}[origin/master]"
    filter.scope.should be_nil
    filter.glob.should eq "packages/**"
    filter.since.should eq "origin/master"
    filter.exclude.should be_false
    filter.include_dependencies.should be_false
    filter.include_dependents.should be_true
    filter.exclude_self.should be_false

    filter = Zap::Utils::Filter.new "{packages/**}[origin/master]..."
    filter.scope.should be_nil
    filter.glob.should eq "packages/**"
    filter.since.should eq "origin/master"
    filter.exclude.should be_false
    filter.include_dependencies.should be_true
    filter.include_dependents.should be_false
    filter.exclude_self.should be_false

    filter = Zap::Utils::Filter.new "...{packages/**}[origin/master]..."
    filter.scope.should be_nil
    filter.glob.should eq "packages/**"
    filter.since.should eq "origin/master"
    filter.exclude.should be_false
    filter.include_dependencies.should be_true
    filter.include_dependents.should be_true
    filter.exclude_self.should be_false

    filter = Zap::Utils::Filter.new "@babel/*{components/**}"
    filter.scope.should eq "@babel/*"
    filter.glob.should eq "components/**"
    filter.since.should be_nil
    filter.exclude.should be_false
    filter.include_dependencies.should be_false
    filter.include_dependents.should be_false
    filter.exclude_self.should be_false

    filter = Zap::Utils::Filter.new "@babel/*{components/**}[origin/master]"
    filter.scope.should eq "@babel/*"
    filter.glob.should eq "components/**"
    filter.since.should eq "origin/master"
    filter.exclude.should be_false
    filter.include_dependencies.should be_false
    filter.include_dependents.should be_false
    filter.exclude_self.should be_false

    filter = Zap::Utils::Filter.new "...[origin/master]"
    filter.scope.should be_nil
    filter.glob.should be_nil
    filter.since.should eq "origin/master"
    filter.exclude.should be_false
    filter.include_dependencies.should be_false
    filter.include_dependents.should be_true
    filter.exclude_self.should be_false

    filter = Zap::Utils::Filter.new "!foo"
    filter.scope.should eq "foo"
    filter.glob.should be_nil
    filter.since.should be_nil
    filter.exclude.should be_true
    filter.include_dependencies.should be_false
    filter.include_dependents.should be_false
    filter.exclude_self.should be_false

    filter = Zap::Utils::Filter.new "!./lib"
    filter.scope.should be_nil
    filter.glob.should eq "lib"
    filter.since.should be_nil
    filter.exclude.should be_true
    filter.include_dependencies.should be_false
    filter.include_dependents.should be_false
    filter.exclude_self.should be_false
  end
end

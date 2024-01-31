require "spec"
require "./ignore"

macro test_gitignore_file(name, should_match, should_not_match)
  describe "{{name.id}}.gitignore" do
    gitignore = Zap::Utils::Git::Ignore.new(File.read("#{__DIR__}/fixtures/{{name.id}}.gitignore").each_line.to_a)

    should_match = {{ should_match }}

    should_not_match = {{ should_not_match }}

    should_match.map { |pattern|
      it "should match \"#{pattern}\"" do
        gitignore.match?(pattern).should be_true
      end
    }
    should_not_match.map { |pattern|
      it "should reject \"#{pattern}\"" do
        gitignore.match?(pattern).should be_false
      end
    }
  end
end

describe Zap::Utils::Git::Ignore, tags: {"utils", "utils.git"} do
  describe ".match?" do
    # https://github.com/github/gitignore/blob/main/Node.gitignore
    test_gitignore_file(
      "Node",
      {
        "npm-debug.log",
        "npm-debug.log-2022-10-20",
        "nested/npm-debug.log-2022-10-20",
        "report.20181221.005011.8974.0.001.json",
        "logs",
        "node_modules/",
        "nested/node_modules/",
        "build/Release",
      },
      {
        "report.json",
        "report.ABC.DEF.json",
        "node_modules",
        "stuff/build/Release",
      }
    )

    # https://github.com/github/gitignore/blob/main/Gradle.gitignore
    test_gitignore_file(
      "Gradle",
      {
        ".gradle",
        "nested/.gradle",
        "build/",
        "nested/build/",
        "nested/folder/build/",
        "nested/src/build/",
        "nested/folder/src/build/",
      },
      {
        "src/build/",
        "src/nested/build/",
        "src/nested/folder/build/",
        "gradle-wrapper.jar",
        "nested/folder/gradle-wrapper.jar",
        "src/gradle-wrapper.properties",
      }
    )

    # https://git-scm.com/docs/gitignore#_see_also
    test_gitignore_file(
      "Exclude",
      {
        "bar",
        "foo/baz",
      },
      {
        "foo",
        "foo/bar",
        "foo/bar/baz",
      }
    )
  end
end

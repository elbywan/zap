require "spec"
require "./workspaces"

alias Workspaces = ::Zap::Workspaces
alias Workspace = ::Zap::Workspaces::Workspace
alias Package = ::Zap::Package

WORKSPACE_A = Workspace.new(
  package: Package.from_json(%({
    "name": "a",
    "version": "1.0.0",
    "dependencies": {
      "b": "^1",
      "c": "workspace:*"
    }
  })),
  path: Path.new("/my-app/pkgs/a"),
  relative_path: Path.new("pkgs/a")
)

WORKSPACE_B = Workspace.new(
  package: Package.from_json(%({
    "name": "b",
    "version": "1.5.0",
    "dependencies": {
      "c": "^2",
      "d": "workspace:*"
    }
  })),
  path: Path.new("/my-app/pkgs/b"),
  relative_path: Path.new("pkgs/b")
)

WORKSPACE_C = Workspace.new(
  package: Package.from_json(%({
    "name": "c",
    "version": "0.3.0",
    "dependencies": {
      "b": "^2"
    }
  })),
  path: Path.new("/my-app/libs/c"),
  relative_path: Path.new("libs/c")
)

WORKSPACE_D = Workspace.new(
  package: Package.from_json(%({
    "name": "d",
    "version": "0.4.0"
  })),
  path: Path.new("/my-app/libs/d"),
  relative_path: Path.new("libs/d")
)

describe Workspaces, tags: "workspaces" do
  it "should compute deep relationships between workspaces" do
    workspaces = Workspaces.new([WORKSPACE_A, WORKSPACE_B, WORKSPACE_C, WORKSPACE_D])
    workspaces.relationships.should eq({
      WORKSPACE_A => Workspaces::Relationships.new(
        direct_dependencies: [WORKSPACE_B, WORKSPACE_C],
        dependencies: Set{WORKSPACE_B, WORKSPACE_C, WORKSPACE_D},
      ),
      WORKSPACE_B => Workspaces::Relationships.new(
        direct_dependencies: [WORKSPACE_D],
        dependencies: Set{WORKSPACE_D},
        direct_dependents: [WORKSPACE_A],
        dependents: Set{WORKSPACE_A},
      ),
      WORKSPACE_C => Workspaces::Relationships.new(
        direct_dependents: [WORKSPACE_A],
        dependents: Set{WORKSPACE_A},
      ),
      WORKSPACE_D => Workspaces::Relationships.new(
        direct_dependents: [WORKSPACE_B],
        dependents: Set{WORKSPACE_B, WORKSPACE_A},
      ),
    })
  end

  it "should raise when a workspace has cycles" do
    workspaces = Workspaces.new([
      Workspace.new(
        package: Package.from_json(%({
          "name": "a",
          "version": "1.0.0",
          "dependencies": {
            "b": "*"
          }
        })),
        path: Path.new("/my-app/pkgs/a"),
        relative_path: Path.new("pkgs/a")
      ),
      Workspace.new(
        package: Package.from_json(%({
          "name": "b",
          "version": "1.0.0",
          "dependencies": {
            "c": "*"
          }
        })),
        path: Path.new("/my-app/pkgs/b"),
        relative_path: Path.new("pkgs/b")
      ),
      Workspace.new(
        package: Package.from_json(%({
          "name": "c",
          "version": "1.0.0",
          "dependencies": {
            "a": "*"
          }
        })),
        path: Path.new("/my-app/pkgs/c"),
        relative_path: Path.new("pkgs/c")
      ),
    ])

    expect_raises Workspaces::CycleException do
      workspaces.relationships
    end
  end

  it "should filter workspaces" do
    # Dummy workspaces
    workspaces = Workspaces.new([WORKSPACE_A, WORKSPACE_B, WORKSPACE_C, WORKSPACE_D])
    # Mock git diff, so we can test the [origin/develop] filter
    workspaces.diffs.inner["origin/develop"] = ["pkgs/a/README", "libs/c/src/main.js"]

    workspaces.filter("b").should eq [WORKSPACE_B]
    workspaces.filter("!b").should eq [WORKSPACE_A, WORKSPACE_C, WORKSPACE_D]
    workspaces.filter("a", "b").should eq [WORKSPACE_A, WORKSPACE_B]
    workspaces.filter("./libs/*").should eq [WORKSPACE_C, WORKSPACE_D]
    workspaces.filter("{pkgs/*}").should eq [WORKSPACE_A, WORKSPACE_B]
    workspaces.filter("{*}").should eq [] of String
    workspaces.filter("./*").should eq [] of String
    workspaces.filter("{**}").should eq [WORKSPACE_A, WORKSPACE_B, WORKSPACE_C, WORKSPACE_D]
    workspaces.filter("./**").should eq [WORKSPACE_A, WORKSPACE_B, WORKSPACE_C, WORKSPACE_D]
    workspaces.filter("...b").should eq [WORKSPACE_A, WORKSPACE_B]
    workspaces.filter("..../pkgs/b").should eq [WORKSPACE_A, WORKSPACE_B]
    workspaces.filter("...{pkgs/b}").should eq [WORKSPACE_A, WORKSPACE_B]
    workspaces.filter("...^b").should eq [WORKSPACE_A]
    workspaces.filter("...^./pkgs/b").should eq [WORKSPACE_A]
    workspaces.filter("...^{pkgs/b}").should eq [WORKSPACE_A]
    workspaces.filter("a...").should eq [WORKSPACE_A, WORKSPACE_B, WORKSPACE_C, WORKSPACE_D]
    workspaces.filter("b...").should eq [WORKSPACE_B, WORKSPACE_D]
    workspaces.filter("{pkgs/a}...").should eq [WORKSPACE_A, WORKSPACE_B, WORKSPACE_C, WORKSPACE_D]
    workspaces.filter("a...", "!...b").should eq [WORKSPACE_C, WORKSPACE_D]
    workspaces.filter("a^...").should eq [WORKSPACE_B, WORKSPACE_C, WORKSPACE_D]
    workspaces.filter("{pkgs/a}^...").should eq [WORKSPACE_B, WORKSPACE_C, WORKSPACE_D]
    workspaces.filter("...b...").should eq [WORKSPACE_A, WORKSPACE_B, WORKSPACE_D]
    workspaces.filter("...^b...").should eq [WORKSPACE_A, WORKSPACE_D]
    workspaces.filter("...b^...").should eq [WORKSPACE_A, WORKSPACE_D]
    workspaces.filter("[origin/develop]").should eq [WORKSPACE_A, WORKSPACE_C]
    workspaces.filter("a[origin/develop]").should eq [WORKSPACE_A]
    workspaces.filter("{pkgs/*}[origin/develop]").should eq [WORKSPACE_A]
    workspaces.filter("./libs/*[origin/develop]").should eq [WORKSPACE_C]
    workspaces.filter("...[origin/develop]").should eq [WORKSPACE_A, WORKSPACE_C]
    workspaces.filter("[origin/develop]...").should eq [WORKSPACE_A, WORKSPACE_B, WORKSPACE_C, WORKSPACE_D]
    workspaces.filter("...^[origin/develop]").should eq [WORKSPACE_A]
    workspaces.filter("[origin/develop]^...").should eq [WORKSPACE_B, WORKSPACE_C, WORKSPACE_D]
  end
end

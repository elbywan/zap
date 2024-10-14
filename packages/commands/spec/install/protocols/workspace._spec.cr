require "../spec_helper"
require "../../../install/protocol/workspace"

module Commands::Install::Protocol::Workspace::Spec
  def self.make_workspaces(*workspace_list : Tuple(String, String))
    Workspaces.new(workspaces: workspace_list.map { |(name, version)|
      Workspaces::Workspace.new(
        package: Data::Package.new(name: name, version: version),
        path: Path.new("/my-app/pkgs/#{name}"),
        relative_path: Path.new("pkgs/#{name}")
      )
    }.to_a)
  end

  describe Protocol::Workspace, tags: "protocol" do
    {
      {"whatever", nil},
    }.each do |(specifier, expected)|
      it "should normalize specifiers (#{specifier})" do
        Protocol::Workspace.normalize?(specifier, nil).should eq(expected)
      end
    end

    it "should raise if the workspace: protocol is used outside a workspace" do
      expect_raises(Exception, "The workspace:* protocol must be used inside a workspace") do
        Protocol::Workspace.resolver?(
          state: SpecHelper::DUMMY_STATE,
          name: "my_package",
          specifier: "workspace:*",
        )
      end
    end

    it "should raise if the workspace: protocol is used by a transitive dependency" do
      expect_raises(Exception, "The workspace:* protocol is forbidden for non-direct dependencies") do
        Protocol::Workspace.resolver?(
          state: SpecHelper::DUMMY_STATE,
          name: "my_package",
          specifier: "workspace:*",
          parent: Data::Package.new("parent", "1.0.0")
        )
      end
    end

    it "should raise if the package is not found in the workspace list" do
      expect_raises(Exception, "Did you forget to add it to the workspace list?") do
        Protocol::Workspace.resolver?(
          state: SpecHelper::DUMMY_STATE.copy_with(context: SpecHelper::DUMMY_STATE.context.copy_with(workspaces: make_workspaces({"other_package", "1.0.0"}))),
          name: "my_package",
          specifier: "workspace:*",
          parent: nil
        )
      end
    end

    {
      {
        "my_package",
        "workspace:*",
        Data::Lockfile::Root.new("root", "0.0.1"),
        make_workspaces({"my_package", "1.0.0"}),
        "*",
      },
      {
        "my_package",
        "^1",
        nil,
        make_workspaces({"my_package", "1.0.0"}),
        "^1",
      },
    }.each do |(name, specifier, parent, workspaces, resolver_specifier)|
      it "should instantiate a resolver" do
        resolver = Protocol::Workspace.resolver?(
          state: SpecHelper::DUMMY_STATE.copy_with(context: SpecHelper::DUMMY_STATE.context.copy_with(workspaces: workspaces)),
          name: name,
          specifier: specifier,
          parent: parent
        )
        resolver.should_not be_nil
        raise "resolver should not be nil" if resolver.nil?
        resolver.name.should eq(name)
        resolver.specifier.should eq(resolver_specifier)
      end
    end

    {
      {
        "my_package",
        "^1",
        Data::Package.new("parent", "1.0.0"), # parent is not a root
        make_workspaces({"my_package", "1.0.0"}),
      },
      {
        "my_package",
        "^1",
        nil,
        make_workspaces({"other_package", "1.0.0"}), # my_package is not in the workspace list
      },
    }.each do |(name, specifier, parent, workspaces)|
      it "should not instantiate a resolver" do
        resolver = Protocol::Workspace.resolver?(
          state: SpecHelper::DUMMY_STATE.copy_with(context: SpecHelper::DUMMY_STATE.context.copy_with(workspaces: workspaces)),
          name: name,
          specifier: specifier,
          parent: parent
        )
        resolver.should be_nil
      end
    end
  end
end

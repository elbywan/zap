require "../base"
require "../resolver"

struct Commands::Install::Protocol::Workspace < Commands::Install::Protocol::Base
end

struct Commands::Install::Protocol::Workspace::Resolver < Commands::Install::Protocol::Resolver
  @workspace : Workspaces::Workspace

  def initialize(
    state,
    name,
    @workspace : Workspaces::Workspace,
    specifier = "latest",
    parent = nil,
    dependency_type = nil,
    skip_cache = false
  )
    super(state, name, specifier, parent, dependency_type, skip_cache)
  end

  def resolve(*, pinned_version : String? = nil) : Data::Package
    if Dir.exists?(@workspace.path)
      Data::Package.init(@workspace.path).tap { |pkg|
        pkg.dist = Data::Package::Dist::Workspace.new(@workspace.package.name)
        on_resolve(pkg)
      }
    else
      raise "Cannot find package #{name} in the current workspace."
    end
  end

  def valid?(metadata : Data::Package) : Bool
    false
  end

  def store?(metadata : Data::Package, &on_downloading) : Bool
    false
  end
end

require "../base"
require "../resolver"

struct Zap::Commands::Install::Protocol::Workspace < Zap::Commands::Install::Protocol::Base
end

struct Zap::Commands::Install::Protocol::Workspace::Resolver < Zap::Commands::Install::Protocol::Resolver
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

  def resolve(*, pinned_version : String? = nil) : Package
    if Dir.exists?(@workspace.path)
      Package.init(@workspace.path).tap { |pkg|
        pkg.dist = Package::Dist::Workspace.new(@workspace.package.name)
        on_resolve(pkg)
      }
    else
      raise "Cannot find package #{name} in the current workspace."
    end
  end

  def valid?(metadata : Package) : Bool
    false
  end

  def store?(metadata : Package, &on_downloading) : Bool
    false
  end
end

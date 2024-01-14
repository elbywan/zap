require "../base"
require "./resolver"

struct Zap::Commands::Install::Protocol::Workspace < Zap::Commands::Install::Protocol::Base
  def self.normalize?(str : String, base_directory : String, path : Path?) : {String?, String?}?
    nil
  end

  def self.resolver?(
    state,
    name,
    specifier = "latest",
    parent = nil,
    dependency_type = nil,
    skip_cache = false
  ) : Protocol::Resolver?
    return nil if name.nil?
    # Check if the package depending on the current one is a workspace
    parent_is_workspace = !parent || parent.is_a?(Lockfile::Root)

    # Partial implementation of the pnpm workspace protocol
    # Does not support aliases for the moment
    # https://pnpm.io/workspaces#workspace-protocol-workspace
    has_workspace_protocol = specifier.starts_with?("workspace:")

    # Check if the package is a workspace
    workspaces = state.context.workspaces
    workspace = begin
      if has_workspace_protocol
        raise "The workspace:* protocol is forbidden for non-direct dependencies." unless parent_is_workspace
        raise "The workspace:* protocol must be used inside a workspace." unless workspaces
        begin
          workspaces.get!(name, specifier)
        rescue e
          raise "Workspace '#{name}' not found but required from package '#{parent.try &.name}' using specifier '#{specifier}'. Did you forget to add it to the workspace list?"
        end
      elsif parent_is_workspace
        workspaces.try(&.get(name, specifier))
      end
    end

    return nil unless workspace

    # Strip the workspace:// prefix
    specifier = specifier[10..]

    # Will link the workspace in the parent node_modules folder
    Log.debug { "(#{name}@#{specifier}) Resolved as a workspace dependency" }
    Resolver.new(state, name, workspace, specifier, parent, dependency_type, skip_cache)
  end
end

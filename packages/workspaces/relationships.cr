require "./workspace"

class Workspaces
  record Relationships,
    dependencies : Set(Workspace) = Set(Workspace).new,
    direct_dependencies : Array(Workspace) = Array(Workspace).new,
    dependents : Set(Workspace) = Set(Workspace).new,
    direct_dependents : Array(Workspace) = Array(Workspace).new
end

# Workspaces

Monorepo support: a root manifest declares members, and commands operate over
the whole set with a shared lockfile and store.

- **Discover the members.** The workspace root and its members come from the
  `workspaces` glob list in the root manifest, and the install and command
  scopes are built from them ([core/config.cr](../packages/core/config.cr)
  `Core::Config#infer_context`, [workspaces/workspace.cr](../packages/workspaces/workspace.cr)
  `Workspaces::Workspace`).

- **Resolve a member locally.** A dependency on a workspace member resolves to
  the local folder (the `workspace:` protocol or a matching version), never to
  the registry, and fails when the member does not exist
  ([install/protocol/workspace/workspace.cr](../packages/commands/install/protocol/workspace/workspace.cr)
  `Protocol::Workspace`).

- **Share one lockfile and one store.** Every member keeps a root in the same
  lockfile, and the graph resolves identically no matter which member
  directory the install starts from ([data/lockfile.cr](../packages/data/lockfile.cr)
  `Data::Lockfile`, [core/config.cr](../packages/core/config.cr)
  `Core::Config#infer_context`).

- **Filter the command scope.** `--filter <pattern>` restricts a command to
  the matching members, `--recursive` applies it to all, `--workspace-root`
  targets the root, and `--ignore-workspaces` ignores the workspace entirely
  ([core/config.cr](../packages/core/config.cr) `Core::Config`,
  [workspaces/filter.cr](../packages/workspaces/filter.cr)
  `Workspaces::Filter`).

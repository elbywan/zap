# Linking

Materialize the resolved graph into the layout the runtime resolves, in one of
three strategies, incrementally so unchanged packages are not re-linked.

- **Pick the linker by strategy.** The classic, isolated, or pnp linker is
  chosen from the install strategy
  ([install.cr](../packages/commands/install/install.cr)
  `Install.link_packages`).

- **Remove the stale packages first.** Declared direct edges that disappeared
  are removed, and orphaned modules from previous installs are pruned
  ([linker/linker.cr](../packages/commands/install/linker/linker.cr)
  `Base#remove`, `Base#prune_orphan_modules`).

- **Link each package, skipping what is already there.** A package is
  materialized into its strategy location with the configured backend
  (hardlink, clonefile, copyfile, copy, symlink), its binaries are linked into
  `.bin`, and packages whose installed-state entry already matches (key and
  patch hash) are skipped
  ([backend/backend.cr](../packages/backend/backend.cr) `Backend`,
  [backend/backend.cr](../packages/backend/backend.cr)
  `InstalledState`, `package_already_installed?`).

  ```text
  link(package, location):
      if installed_state.matches(package.key, location, patch_hash):
          return
      backend.materialize(store_path(package), location)
      link_binaries(package, location)
      installed_state.record(package, location, patch_hash)
  ```

- **Hoist in the classic strategy.** A package goes to the root `node_modules`
  when it matches the hoisting patterns and nothing conflicts, otherwise it
  stays nested under its dependent
  ([linker/classic/classic.cr](../packages/commands/install/linker/classic/classic.cr)
  `Linker::Classic`).

- **Build the isolated store.** One `.store` folder per package with its own
  `node_modules`, plus a symlink from the top level for each edge
  ([linker/isolated/isolated.cr](../packages/commands/install/linker/isolated/isolated.cr)
  `Linker::Isolated`).

- **Generate the pnp runtime.** A `.pnp.cjs` plus a `.pnp.data.json` map every
  package and subpath to its store location; a package with a distinct peer
  set gets a distinct virtual identity
  ([linker/pnp/pnp.cr](../packages/commands/install/linker/pnp/pnp.cr)
  `Linker::PnP`).

- **Persist the installed state.** After linking, the state is saved so the
  next install can skip the unchanged packages
  ([backend/backend.cr](../packages/backend/backend.cr)
  `InstalledState.save`).

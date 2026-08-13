# Lifecycle scripts

When dependency build scripts run, and how the order and the policy are
decided. A script is `preinstall`, `install`, or `postinstall` from the
package manifest, plus the implicit `node-gyp rebuild` injected for a package
that ships a `binding.gyp` and no explicit `install` script.

## The policy, as a table

| Configuration | Dependency scripts | Project's own scripts |
| --- | --- | --- |
| default | none (each skipped package is warned once) | run |
| package in `zap.only_built_dependencies` | that package runs | run |
| package in `zap.ignored_built_dependencies` | skip, no warning | run |
| `zap.dangerously_allow_all_builds: true` | all packages run | run |
| `--ignore-scripts` | none | none |
| `zap dlx` / `zap rebuild` (explicit) | run regardless of the policy | run |

## Specs

- **Register the hooks.** A package is registered as having install hooks
  when it declares `preinstall`/`install`/`postinstall`, or when it has a
  `binding.gyp` without an explicit `install` script (which injects
  `node-gyp rebuild`) (the linkers' hook registration,
  [lifecycle_scripts.cr](../packages/data/package/lifecycle_scripts.cr)
  `has_install_script?`).

- **Respect `--ignore-scripts`.** With it, or with no hooked packages, no
  script runs at all ([install.cr](../packages/commands/install/install.cr)
  `Install.run_install_hooks`).

- **Split the hooks into run and skip.** A package runs when
  `dangerously_allow_all_builds` is set or its name is in
  `only_built_dependencies`; otherwise it is skipped and warned about, unless
  it is in `ignored_built_dependencies`
  ([install.cr](../packages/commands/install/install.cr)
  `Install.filter_build_hooks`).

  ```text
  filter(hooks):
      allow_all = zap.dangerously_allow_all_builds          # default false
      allowlist = zap.only_built_dependencies               # default []
      ignored   = zap.ignored_built_dependencies            # default []
      for (package, path) in hooks:
          if allow_all or package.name in allowlist:
              to_run.append(package, path)
          elif package.name not in ignored:
              skipped.append("#{package.name}@#{package.version}")
  ```

- **Warn once about the skipped packages**, pointing at `zap approve-builds`
  and the allowlist key ([install.cr](../packages/commands/install/install.cr)
  `run_install_hooks`).

- **Run in dependency order.** The allowed hooks run with dependencies before
  their dependents, and within a package in the order `preinstall`, `install`,
  `postinstall`; a failing script fails the install
  ([install.cr](../packages/commands/install/install.cr)
  `run_install_hooks`, `hook_depth`).

  ```text
  run_install_hooks(linker):
      (to_run, skipped) = filter(linker.installed_packages_with_hooks)
      if skipped: info("Ignored build scripts: ...")
      for (package, path) in sort_by_depth(to_run):      # deps first
          for script in [preinstall, install, postinstall]:
              run_script(script, path)                   # failure aborts
  ```

- **Run the project's own scripts.** The root and the workspace members run
  their own scripts regardless of the allowlist, but not under
  `--ignore-scripts` ([install.cr](../packages/commands/install/install.cr)
  `Install.run_own_install_hooks`).

- **Review and approve.** `zap approve-builds` lists the packages with pending
  build scripts (the resolved `hasInstallScript` flag, plus the `binding.gyp`
  builds found in the store) and writes the choices into
  `only_built_dependencies` and `ignored_built_dependencies`
  ([approve-builds/approve-builds.cr](../packages/commands/approve-builds/approve-builds.cr)
  `pending_packages`, `write_approvals`).

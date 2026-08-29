# Pack

Turn a local package — including workspace members — into a self-contained,
deterministic, installable tarball, like npm / pnpm / yarn do. Yarn-berry
behavior is the reference; npm / pnpm conventions apply where berry is
silent.

- **Pack a package directory.** The command reads the `package.json` at the
  given path (default: the project prefix), requires a `name`, defaults a
  missing `version` to `0.0.0`, and writes the archive
  ([pack.cr](../packages/commands/pack/pack.cr) `Commands::Pack.run`).

  ```text
  pack(path):
      manifest = read(package.json)        # error if missing
      name     = manifest.name             # error if missing
      version  = manifest.version ?? 0.0.0
      archive  = out ?? path / "package.tgz"
      files    = select(path, manifest)    # see below
      write_tarball(path, files, archive)
  ```

- **The output name.** The default is `package.tgz` in the package
  directory (yarn parity). `-o/--out` sets the path, interpolating `%s`
  (the slugified name: `@scope/name` → `scope-name`) and `%v` (the
  version), resolved against the current directory
  ([cli.cr](../packages/commands/pack/cli.cr), `resolve_output`).

- **Select the files.** The `files` whitelist is honored, with a matched
  directory carrying its whole subtree; `main` and `bin` are always
  included; README / LICENSE / package.json are always included;
  `.npmignore` (preferred) or `.gitignore` exclusions apply; `node_modules`,
  `.git` and the always-ignored entries never are; the output archive is
  never packed into itself; a malformed `files` field fails loudly
  ([pack.cr](../packages/commands/pack/pack.cr) `collect_files`,
  `include_patterns`, `ignore_patterns`).

- **Packing is deterministic.** Entries are sorted, the tar entry modes are
  normalized (bin entries `0755`, everything else `0644`), and both the tar
  and the gzip headers carry a fixed timestamp — two packs of the same
  input are byte-identical
  ([pack.cr](../packages/commands/pack/pack.cr) `write_archive`,
  [targzip.cr](../packages/utils/targzip.cr) `TarGzip.pack_file`).

- **The layout is npm-compatible.** Contents live under a `package/`
  prefix, which both npm and zap strip when installing: the tarball
  installs through a `file:` dependency and with `npm install <tarball>`.

- **Symlinks are packed as their target.** The installer cannot recreate
  links, so a symlink is packed as a regular file's content or a linked
  directory's tree; a linked directory is followed unless it resolves into
  one of its own ancestors (a link cycle), and dangling links are skipped.

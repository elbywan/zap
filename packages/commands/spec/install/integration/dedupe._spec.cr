require "../../../catalog/catalog"
require "./spec_helper"

# The prefer-dedupe resolution: when a compatible version of a package is
# already used in the tree, a new dependency resolves to the highest used
# version instead of a fresh one (pnpm's prefer-dedupe semantics).
# A plain install with the given package.json; returns the project dir.
private def dedupe_install(registry, package_json : String) : Path
  tmpdir = Path.new(Dir.tempdir, "zap-it-#{Random::Secure.hex(4)}")
  Dir.mkdir_p(tmpdir)
  File.write(tmpdir / "package.json", package_json)
  File.write(tmpdir / ".npmrc", "registry=#{registry.base_url}/\n")
  config = Core::Config.new.copy_with(prefix: tmpdir.to_s, store_path: (tmpdir / "store").to_s, silent: true)
  ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true)
  Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)
  tmpdir
end

describe "prefer-dedupe", tags: "integration" do
  it "collapses two compatible ranges into the highest used version" do
    It.with_registry do |registry|
      registry.add("dep", "1.0.0", It.pkg("dep", "1.0.0"), {"index.js" => "1.0.0"})
      registry.add("dep", "1.2.0", It.pkg("dep", "1.2.0"), {"index.js" => "1.2.0"})
      registry.add("a", "1.0.0", It.pkg("a", "1.0.0", dependencies: {"dep" => "^1.0.0"}), {"index.js" => "a"})
      registry.add("b", "1.0.0", It.pkg("b", "1.0.0", dependencies: {"dep" => "~1.2.0"}), {"index.js" => "b"})

      project = dedupe_install(registry, %({"name":"app","version":"1.0.0","dependencies":{"a":"1.0.0","b":"1.0.0"}}))
      begin
        # Both ranges are compatible with 1.2.0: one version in the tree.
        lockfile = Data::Lockfile.new(project)
        dep_versions = lockfile.packages.keys.select { |k| k.starts_with?("dep@") }
        dep_versions.size.should eq(1)
        dep_versions.first.should eq("dep@1.2.0")
      ensure
        FileUtils.rm_rf(project)
      end
    end
  end

  it "does not downgrade when no used version satisfies the range" do
    It.with_registry do |registry|
      registry.add("dep", "1.0.0", It.pkg("dep", "1.0.0"), {"index.js" => "1.0.0"})
      registry.add("dep", "2.0.0", It.pkg("dep", "2.0.0"), {"index.js" => "2.0.0"})
      registry.add("a", "1.0.0", It.pkg("a", "1.0.0", dependencies: {"dep" => "^1.0.0"}), {"index.js" => "a"})
      registry.add("b", "1.0.0", It.pkg("b", "1.0.0", dependencies: {"dep" => "^2.0.0"}), {"index.js" => "b"})

      project = dedupe_install(registry, %({"name":"app","version":"1.0.0","dependencies":{"a":"1.0.0","b":"1.0.0"}}))
      begin
        # The ranges are incompatible: both versions stay.
        lockfile = Data::Lockfile.new(project)
        dep_versions = lockfile.packages.keys.select { |k| k.starts_with?("dep@") }
        dep_versions.sort.should eq(["dep@1.0.0", "dep@2.0.0"])
      ensure
        FileUtils.rm_rf(project)
      end
    end
  end

  it "shares one version across workspace members" do
    It.with_registry do |registry|
      registry.add("dep", "1.0.0", It.pkg("dep", "1.0.0"), {"index.js" => "1.0.0"})
      registry.add("dep", "1.3.0", It.pkg("dep", "1.3.0"), {"index.js" => "1.3.0"})

      ws_root = Path.new(Dir.tempdir, "zap-ws-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(ws_root / "packages/a")
        Dir.mkdir_p(ws_root / "packages/b")
        File.write(ws_root / "package.json", %({"name":"ws","version":"1.0.0","workspaces":["packages/*"]}))
        File.write(ws_root / ".npmrc", "registry=#{registry.base_url}/\n")
        File.write(ws_root / "packages/a/package.json", %({"name":"a","version":"1.0.0","dependencies":{"dep":"^1.0.0"}}))
        File.write(ws_root / "packages/b/package.json", %({"name":"b","version":"1.0.0","dependencies":{"dep":"~1.3.0"}}))
        config = Core::Config.new.copy_with(prefix: ws_root.to_s, store_path: (ws_root / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)

        lockfile = Data::Lockfile.new(ws_root)
        dep_versions = lockfile.packages.keys.select { |k| k.starts_with?("dep@") }
        dep_versions.size.should eq(1)
        dep_versions.first.should eq("dep@1.3.0")
      ensure
        FileUtils.rm_rf(ws_root)
      end
    end
  end

  it "keeps the fresh resolution when prefer_dedupe is disabled" do
    It.with_registry do |registry|
      registry.add("dep", "1.0.0", It.pkg("dep", "1.0.0"), {"index.js" => "1.0.0"})
      registry.add("dep", "1.2.0", It.pkg("dep", "1.2.0"), {"index.js" => "1.2.0"})
      registry.add("a", "1.0.0", It.pkg("a", "1.0.0", dependencies: {"dep" => "^1.0.0"}), {"index.js" => "a"})
      registry.add("b", "1.0.0", It.pkg("b", "1.0.0", dependencies: {"dep" => "~1.2.0"}), {"index.js" => "b"})

      # With the dedupe disabled, the two ranges resolve independently and
      # stay distinct when the registry offers a version only one accepts:
      # ^1.0.0 picks 1.2.0 while ~1.0.0 can only use 1.0.0.
      registry.add("dep", "1.0.0", It.pkg("dep", "1.0.0"), {"index.js" => "1.0.0"})
      registry.add("dep", "1.2.0", It.pkg("dep", "1.2.0"), {"index.js" => "1.2.0"})
      registry.add("a", "1.0.0", It.pkg("a", "1.0.0", dependencies: {"dep" => "^1.0.0"}), {"index.js" => "a"})
      registry.add("b", "1.0.0", It.pkg("b", "1.0.0", dependencies: {"dep" => "~1.0.0"}), {"index.js" => "b"})

      project = dedupe_install(registry, %({"name":"app","version":"1.0.0","zap":{"prefer_dedupe":false},"dependencies":{"a":"1.0.0","b":"1.0.0"}}))
      begin
        lockfile = Data::Lockfile.new(project)
        dep_versions = lockfile.packages.keys.select { |k| k.starts_with?("dep@") }
        dep_versions.sort.should eq(["dep@1.0.0", "dep@1.2.0"])
      ensure
        FileUtils.rm_rf(project)
      end
    end
  end

  # The one-shot `zap dedupe` pass: a tree that already holds compatible
  # but different versions (installed before the dedupe existed, or with
  # the option off) is re-resolved and collapsed into the highest version
  # in use. The divergence is built with two sequential installs: dep 1.2.0
  # does not exist when `a` pins 1.0.0, and is published before `b` pins it.
  # The ranges are declared by the workspace members (direct dependencies),
  # so the re-resolution still knows them: transitive pins in the lockfile
  # are exact and stay authoritative.
  it "collapses a pre-diverged tree with the one-shot dedupe pass" do
    It.with_registry do |registry|
      registry.add("dep", "1.0.0", It.pkg("dep", "1.0.0"), {"index.js" => "1.0.0"})
      registry.add("a", "1.0.0", It.pkg("a", "1.0.0", dependencies: {"dep" => "^1.0.0"}), {"index.js" => "a"})

      ws_root = Path.new(Dir.tempdir, "zap-wsdd-#{Random::Secure.hex(4)}")
      Dir.mkdir_p(ws_root / "packages/a")
      File.write(ws_root / "package.json", %({"name":"ws","version":"1.0.0","workspaces":["packages/*"]}))
      File.write(ws_root / ".npmrc", "registry=#{registry.base_url}/\n")
      config = Core::Config.new.copy_with(prefix: ws_root.to_s, store_path: (ws_root / "store").to_s, silent: true)
      ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true)
      begin
        # Stage 1: only member `a` exists; dep 1.2.0 is not published yet,
        # so `a` pins dep@1.0.0.
        File.write(ws_root / "packages/a/package.json", %({"name":"a","version":"1.0.0","dependencies":{"dep":"^1.0.0"}}))
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)

        # Stage 2: dep 1.2.0 (and a newer 1.3.0 that only a fresh
        # resolution would adopt) and member `b` appear; `b` pins dep@1.2.0
        # while `a` keeps its pin: the tree is diverged.
        registry.add("dep", "1.2.0", It.pkg("dep", "1.2.0"), {"index.js" => "1.2.0"})
        registry.add("dep", "1.3.0", It.pkg("dep", "1.3.0"), {"index.js" => "1.3.0"})
        Dir.mkdir_p(ws_root / "packages/b")
        File.write(ws_root / "packages/b/package.json", %({"name":"b","version":"1.0.0","dependencies":{"dep":"~1.2.0"}}))
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)

        lockfile = Data::Lockfile.new(ws_root)
        dep_versions = lockfile.packages.keys.select { |k| k.starts_with?("dep@") }
        dep_versions.sort.should eq(["dep@1.0.0", "dep@1.2.0"])
        # The classic linker hoists one version to the root and nests the
        # other under its parent: two physical copies in the tree.
        Dir.glob(ws_root / "**/node_modules/dep/package.json").map { |p| JSON.parse(File.read(p))["version"].as_s }.sort.should eq(["1.0.0", "1.2.0"])

        # The one-shot pass re-resolves the whole tree with the dedupe
        # preference: `a`'s ^1.0.0 accepts the used 1.2.0, so the tree
        # collapses to a single version.
        ic2 = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true, dedupe: true, update_all: true, update_recursive: true)
        Commands::Install.run(config, ic2, raise_on_failure: true, reporter: Reporter::Null.new)

        lockfile = Data::Lockfile.new(ws_root)
        dep_versions = lockfile.packages.keys.select { |k| k.starts_with?("dep@") }
        dep_versions.size.should eq(1)
        dep_versions.first.should eq("dep@1.2.0")
        # The old nested copy is pruned (its lockfile key is gone) and the
        # single remaining version is hoisted to the root: exactly one
        # physical copy, at the top level.
        Dir.glob(ws_root / "**/node_modules/dep/package.json").map { |p| JSON.parse(File.read(p))["version"].as_s }.should eq(["1.2.0"])
        JSON.parse(File.read(ws_root / "node_modules/dep/package.json"))["version"].as_s.should eq("1.2.0")
        File.exists?(ws_root / "packages/a/node_modules/dep").should be_false

        # PROBE: physical layout after the divergence
        Dir.glob(ws_root / "**/node_modules/dep/package.json").each do |p|
          v = JSON.parse(File.read(p))["version"]
          STDERR.puts "PROBE div #{p.gsub(ws_root.to_s, "")} -> dep@#{v}"
        end

        # The one-shot pass re-resolves the whole tree with the dedupe
        # preference: `a`'s ^1.0.0 accepts the used 1.2.0, so the tree
        # collapses to a single version.
        ic2 = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true, dedupe: true, update_all: true, update_recursive: true)
        Commands::Install.run(config, ic2, raise_on_failure: true, reporter: Reporter::Null.new)

        lockfile = Data::Lockfile.new(ws_root)
        dep_versions = lockfile.packages.keys.select { |k| k.starts_with?("dep@") }
        dep_versions.size.should eq(1)
        dep_versions.first.should eq("dep@1.2.0")

        # With prefer-dedupe off the pass has nothing to collapse: it must
        # keep the lockfile pins instead of re-resolving fresh (the tree
        # would otherwise be silently upgraded to the newest versions).
        ic3 = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true, dedupe: true, update_all: true, update_recursive: true, prefer_dedupe: false)
        Commands::Install.run(config, ic3, raise_on_failure: true, reporter: Reporter::Null.new)

        lockfile = Data::Lockfile.new(ws_root)
        dep_versions = lockfile.packages.keys.select { |k| k.starts_with?("dep@") }
        dep_versions.size.should eq(1)
        dep_versions.first.should eq("dep@1.2.0")
      ensure
        FileUtils.rm_rf(ws_root)
      end
    end
  end

  # A regular root app (no workspaces): the divergence is between two
  # transitive dependencies, whose declared ranges are not recorded in the
  # lockfile (only the resolved pins are). The one-shot pass re-fetches the
  # parents' manifests so the declared ranges drive the re-resolution, and
  # the physical tree relocates in the same pass.
  it "collapses a transitive divergence in a regular root app" do
    It.with_registry do |registry|
      registry.add("dep", "1.0.0", It.pkg("dep", "1.0.0"), {"index.js" => "1.0.0"})
      registry.add("a", "1.0.0", It.pkg("a", "1.0.0", dependencies: {"dep" => "^1.0.0"}), {"index.js" => "a"})

      project = Path.new(Dir.tempdir, "zap-nest-#{Random::Secure.hex(4)}")
      Dir.mkdir_p(project)
      File.write(project / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"a":"1.0.0"}}))
      File.write(project / ".npmrc", "registry=#{registry.base_url}/\n")
      config = Core::Config.new.copy_with(prefix: project.to_s, store_path: (project / "store").to_s, silent: true)
      ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true)
      begin
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)

        # dep 1.2.0 and `b` appear; `a` keeps its pin while `b` pins 1.2.0:
        # the tree diverges and the classic linker nests 1.2.0 under `b`
        # (the root already holds 1.0.0).
        registry.add("dep", "1.2.0", It.pkg("dep", "1.2.0"), {"index.js" => "1.2.0"})
        registry.add("b", "1.0.0", It.pkg("b", "1.0.0", dependencies: {"dep" => "~1.2.0"}), {"index.js" => "b"})
        File.write(project / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"a":"1.0.0","b":"1.0.0"}}))
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)

        lockfile = Data::Lockfile.new(project)
        dep_versions = lockfile.packages.keys.select { |k| k.starts_with?("dep@") }
        dep_versions.sort.should eq(["dep@1.0.0", "dep@1.2.0"])
        Dir.glob(project / "**/node_modules/dep/package.json").map { |p| JSON.parse(File.read(p))["version"].as_s }.sort.should eq(["1.0.0", "1.2.0"])

        # The one-shot pass: the declared ranges come back from the fresh
        # parent manifests, so the transitive divergence collapses, and the
        # stale nested copy is pruned in the same pass (the surviving
        # version is hoisted to the root).
        ic2 = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true, dedupe: true, update_all: true, update_recursive: true, force_metadata_retrieval: true)
        Commands::Install.run(config, ic2, raise_on_failure: true, reporter: Reporter::Null.new)

        lockfile = Data::Lockfile.new(project)
        dep_versions = lockfile.packages.keys.select { |k| k.starts_with?("dep@") }
        dep_versions.size.should eq(1)
        dep_versions.first.should eq("dep@1.2.0")
        Dir.glob(project / "**/node_modules/dep/package.json").map { |p| JSON.parse(File.read(p))["version"].as_s }.should eq(["1.2.0"])
        File.exists?(project / "node_modules/b/node_modules/dep").should be_false
      ensure
        FileUtils.rm_rf(project)
      end
    end
  end

  # The dedupe candidate path reuses an already-resolved version without a
  # fresh resolver.resolve, so the on_resolve pin (the resolved version in
  # the parent's specifier) must be recorded explicitly. The isolated and
  # pnp linkers key their lookups on name@<resolved version>.
  ["isolated", "pnp"].each do |strategy_name|
    it "pins the resolved version when the dedupe candidate is reused (#{strategy_name})" do
      strategy = strategy_name == "pnp" ? Data::Package::InstallStrategy::Pnp : Data::Package::InstallStrategy::Isolated
      It.with_registry do |registry|
        registry.add("dep", "1.0.0", It.pkg("dep", "1.0.0"), {"index.js" => "1.0.0"})
        registry.add("a", "1.0.0", It.pkg("a", "1.0.0", dependencies: {"dep" => "^1.0.0"}), {"index.js" => "a"})
        registry.add("b", "1.0.0", It.pkg("b", "1.0.0", dependencies: {"dep" => "^1.0.0"}), {"index.js" => "b"})
        project = Path.new(Dir.tempdir, "zap-pin-#{Random::Secure.hex(4)}")
        Dir.mkdir_p(project)
        File.write(project / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"a":"1.0.0","b":"1.0.0"}}))
        File.write(project / ".npmrc", "registry=#{registry.base_url}/\n")
        config = Core::Config.new.copy_with(prefix: project.to_s, store_path: (project / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true, strategy: strategy)
        begin
          Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)
          lockfile = Data::Lockfile.new(project)
          b = lockfile.packages.values.find { |p| p.name == "b" }
          b.should_not be_nil
          b.not_nil!.dependencies.should eq({"dep" => "1.0.0"})
        ensure
          FileUtils.rm_rf(project)
        end
      end
    end
  end

  # The other install strategies must survive the one-shot pass too: the
  # dedupe restores the declared ranges from the fresh manifests for the
  # subtree resolution, but the lockfile entries must keep their resolved
  # pins (the pnp linker keys its lookups on `name@<resolved version>`).
  ["isolated", "pnp"].each do |strategy_name|
    it "keeps the resolved pins when deduping with the #{strategy_name} strategy" do
      strategy = strategy_name == "pnp" ? Data::Package::InstallStrategy::Pnp : Data::Package::InstallStrategy::Isolated
      It.with_registry do |registry|
        registry.add("dep", "1.0.0", It.pkg("dep", "1.0.0"), {"index.js" => "1.0.0"})
        registry.add("a", "1.0.0", It.pkg("a", "1.0.0", dependencies: {"dep" => "^1.0.0"}), {"index.js" => "a"})
        project = Path.new(Dir.tempdir, "zap-strat-#{Random::Secure.hex(4)}")
        Dir.mkdir_p(project)
        File.write(project / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"a":"1.0.0"}}))
        File.write(project / ".npmrc", "registry=#{registry.base_url}/\n")
        config = Core::Config.new.copy_with(prefix: project.to_s, store_path: (project / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true, strategy: strategy)
        begin
          Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)
          registry.add("dep", "1.2.0", It.pkg("dep", "1.2.0"), {"index.js" => "1.2.0"})
          registry.add("b", "1.0.0", It.pkg("b", "1.0.0", dependencies: {"dep" => "~1.2.0"}), {"index.js" => "b"})
          File.write(project / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"a":"1.0.0","b":"1.0.0"}}))
          Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)

          ic2 = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true, strategy: strategy, dedupe: true, update_all: true, update_recursive: true, force_metadata_retrieval: true)
          Commands::Install.run(config, ic2, raise_on_failure: true, reporter: Reporter::Null.new)

          lockfile = Data::Lockfile.new(project)
          dep_versions = lockfile.packages.keys.select { |k| k.starts_with?("dep@") }
          dep_versions.size.should eq(1)
          dep_versions.first.should eq("dep@1.2.0")
          b = lockfile.packages.values.find { |p| p.name == "b" }
          b.should_not be_nil
          b.not_nil!.dependencies.should eq({"dep" => "1.2.0"})
        ensure
          FileUtils.rm_rf(project)
        end
      end
    end
  end
end

describe "dedupe candidate pins", tags: "integration" do
  it "pins a shared devDependency into the root even when resolved via the candidate" do
    It.with_registry do |registry|
      registry.add("chalk", "4.1.2", It.pkg("chalk", "4.1.2"), {"index.js" => "c"})
      registry.add("other", "1.0.0", It.pkg("other", "1.0.0", dependencies: {"chalk" => "4.1.2"}), {"index.js" => "o"})
      project = Path.new(Dir.tempdir, "zap-cand-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(project / "apps" / "app1")
        File.write(project / "package.json", %({"name":"root","version":"1.0.0","private":true,"workspaces":["apps/*"],"dependencies":{"app1":"workspace:*"},"devDependencies":{"chalk":"4.1.2"}}))
        File.write(project / "apps/app1/package.json", %({"name":"app1","version":"1.0.0","dependencies":{"other":"1.0.0"}}))
        File.write(project / ".npmrc", "registry=#{registry.base_url}/\n")
        config = Core::Config.new.copy_with(prefix: project.to_s, store_path: (project / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true, strategy: Data::Package::InstallStrategy::Isolated)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)
        lf = Data::Lockfile.new(project)
        lf.roots["root"].pinned_dependencies.try(&.["chalk"]?).should eq("4.1.2")
        File.exists?(project / "node_modules/chalk").should be_true
      ensure
        FileUtils.rm_rf(project)
      end
    end
  end
end

describe "dedupe alias pins", tags: "integration" do
  it "keeps aliased dependencies as aliases through the one-shot dedupe pass" do
    It.with_registry do |registry|
      registry.add("real", "1.0.0", It.pkg("real", "1.0.0"), {"index.js" => "1.0.0"})
      registry.add("real", "1.2.0", It.pkg("real", "1.2.0"), {"index.js" => "1.2.0"})
      registry.add("a", "1.0.0", It.pkg("a", "1.0.0", dependencies: {"al" => "npm:real@^1.0.0"}), {"index.js" => "a"})
      project = Path.new(Dir.tempdir, "zap-dedupe-alias-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(project)
        File.write(project / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"a":"1.0.0"}}))
        File.write(project / ".npmrc", "registry=#{registry.base_url}/\n")
        config = Core::Config.new.copy_with(prefix: project.to_s, store_path: (project / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)
        Commands::Install.run(config, ic.copy_with(dedupe: true, update_all: true, update_recursive: true, force_metadata_retrieval: true), raise_on_failure: true, reporter: Reporter::Null.new)
        lf = Data::Lockfile.new(project)
        a = lf.packages.values.find { |p| p.name == "a" }
        a.try(&.dependencies).try(&.["al"]?).should eq(Data::Package::Alias.new("real", "1.2.0"))
        # A bare string pin would make a later install resolve the alias
        # name from the registry; the reinstall must keep working.
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)
      ensure
        FileUtils.rm_rf(project)
      end
    end
  end
end

describe "dedupe corner cases", tags: "integration" do
  it "collapses shared dependencies under the catalog protocol" do
    It.with_registry do |registry|
      registry.add("dep", "1.0.0", It.pkg("dep", "1.0.0"), {"index.js" => "1.0.0"})
      registry.add("dep", "1.2.0", It.pkg("dep", "1.2.0"), {"index.js" => "1.2.0"})
      registry.add("a", "1.0.0", It.pkg("a", "1.0.0", dependencies: {"dep" => "^1.0.0"}), {"index.js" => "a"})
      registry.add("b", "1.0.0", It.pkg("b", "1.0.0", dependencies: {"dep" => "^1.0.0"}), {"index.js" => "b"})
      project = Path.new(Dir.tempdir, "zap-dedupe-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(project)
        File.write(project / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"a":"1.0.0","b":"1.0.0"},"zap":{"catalog":{"dep":"^1.0.0"}}}))
        File.write(project / ".npmrc", "registry=#{registry.base_url}/\n")
        config = Core::Config.new.copy_with(prefix: project.to_s, store_path: (project / "store").to_s, silent: true)
        Commands::Install.run(config, Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true), raise_on_failure: true, reporter: Reporter::Null.new)
        lf = Data::Lockfile.new(project)
        lf.packages.keys.count { |k| k.starts_with?("dep@") }.should eq(1)
        lf.packages.keys.any? { |k| k == "dep@1.2.0" }.should be_true
      ensure
        FileUtils.rm_rf(project)
      end
    end
  end

  it "applies package extensions to deduped packages" do
    It.with_registry do |registry|
      registry.add("extra", "1.0.0", It.pkg("extra", "1.0.0"), {"index.js" => "e"})
      registry.add("dep", "1.0.0", It.pkg("dep", "1.0.0"), {"index.js" => "1.0.0"})
      registry.add("dep", "1.2.0", It.pkg("dep", "1.2.0", dependencies: {"extra" => "1.0.0"}), {"index.js" => "1.2.0"})
      registry.add("a", "1.0.0", It.pkg("a", "1.0.0", dependencies: {"dep" => "^1.0.0"}), {"index.js" => "a"})
      registry.add("b", "1.0.0", It.pkg("b", "1.0.0", dependencies: {"dep" => "^1.0.0"}), {"index.js" => "b"})
      project = Path.new(Dir.tempdir, "zap-dedupe-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(project)
        File.write(project / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"a":"1.0.0","b":"1.0.0"},"zap":{"package_extensions":{"dep@1.0.0":{"dependencies":{"extra":"1.0.0"}}}}}))
        File.write(project / ".npmrc", "registry=#{registry.base_url}/\n")
        config = Core::Config.new.copy_with(prefix: project.to_s, store_path: (project / "store").to_s, silent: true)
        Commands::Install.run(config, Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true), raise_on_failure: true, reporter: Reporter::Null.new)
        lf = Data::Lockfile.new(project)
        lf.packages.keys.count { |k| k.starts_with?("dep@") }.should eq(1)
        lf.packages.values.any? { |p| p.name == "extra" }.should be_true
      ensure
        FileUtils.rm_rf(project)
      end
    end
  end

  it "dedupes under the classic and classic_shallow strategies" do
    It.with_registry do |registry|
      registry.add("dep", "1.0.0", It.pkg("dep", "1.0.0"), {"index.js" => "1.0.0"})
      registry.add("dep", "1.2.0", It.pkg("dep", "1.2.0"), {"index.js" => "1.2.0"})
      registry.add("a", "1.0.0", It.pkg("a", "1.0.0", dependencies: {"dep" => "^1.0.0"}), {"index.js" => "a"})
      registry.add("b", "1.0.0", It.pkg("b", "1.0.0", dependencies: {"dep" => "^1.0.0"}), {"index.js" => "b"})
      [Data::Package::InstallStrategy::Classic, Data::Package::InstallStrategy::Classic_Shallow].each do |strategy|
        project = Path.new(Dir.tempdir, "zap-dedupe-#{Random::Secure.hex(4)}")
        begin
          Dir.mkdir_p(project)
          File.write(project / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"a":"1.0.0","b":"1.0.0"}}))
          File.write(project / ".npmrc", "registry=#{registry.base_url}/\n")
          config = Core::Config.new.copy_with(prefix: project.to_s, store_path: (project / "store").to_s, silent: true)
          Commands::Install.run(config, Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true, strategy: strategy), raise_on_failure: true, reporter: Reporter::Null.new)
          lf = Data::Lockfile.new(project)
          lf.packages.keys.count { |k| k.starts_with?("dep@") }.should eq(1)
        ensure
          FileUtils.rm_rf(project)
        end
      end
    end
  end

  it "respects overrides through the one-shot dedupe pass" do
    It.with_registry do |registry|
      registry.add("dep", "1.0.0", It.pkg("dep", "1.0.0"), {"index.js" => "1.0.0"})
      registry.add("dep", "1.2.0", It.pkg("dep", "1.2.0"), {"index.js" => "1.2.0"})
      registry.add("a", "1.0.0", It.pkg("a", "1.0.0", dependencies: {"dep" => "^1.0.0"}), {"index.js" => "a"})
      registry.add("b", "1.0.0", It.pkg("b", "1.0.0", dependencies: {"dep" => "^1.0.0"}), {"index.js" => "b"})
      project = Path.new(Dir.tempdir, "zap-dedupe-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(project)
        File.write(project / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"a":"1.0.0","b":"1.0.0"},"overrides":{"dep":"1.0.0"}}))
        File.write(project / ".npmrc", "registry=#{registry.base_url}/\n")
        config = Core::Config.new.copy_with(prefix: project.to_s, store_path: (project / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)
        Commands::Install.run(config, ic.copy_with(dedupe: true, update_all: true, update_recursive: true, force_metadata_retrieval: true), raise_on_failure: true, reporter: Reporter::Null.new)
        lf = Data::Lockfile.new(project)
        lf.packages.keys.count { |k| k.starts_with?("dep@") }.should eq(1)
        lf.packages.keys.any? { |k| k == "dep@1.0.0" }.should be_true
      ensure
        FileUtils.rm_rf(project)
      end
    end
  end

  it "keeps optional aliases aliased through the one-shot dedupe pass" do
    It.with_registry do |registry|
      registry.add("real", "1.0.0", It.pkg("real", "1.0.0"), {"index.js" => "1.0.0"})
      registry.add("real", "1.2.0", It.pkg("real", "1.2.0"), {"index.js" => "1.2.0"})
      registry.add("a", "1.0.0", It.pkg("a", "1.0.0", optional_dependencies: {"al" => "npm:real@^1.0.0"}), {"index.js" => "a"})
      project = Path.new(Dir.tempdir, "zap-dedupe-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(project)
        File.write(project / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"a":"1.0.0"}}))
        File.write(project / ".npmrc", "registry=#{registry.base_url}/\n")
        config = Core::Config.new.copy_with(prefix: project.to_s, store_path: (project / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)
        Commands::Install.run(config, ic.copy_with(dedupe: true, update_all: true, update_recursive: true, force_metadata_retrieval: true), raise_on_failure: true, reporter: Reporter::Null.new)
        lf = Data::Lockfile.new(project)
        a = lf.packages.values.find { |p| p.name == "a" }
        a.try(&.optional_dependencies).try(&.["al"]?).should eq(Data::Package::Alias.new("real", "1.2.0"))
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)
      ensure
        FileUtils.rm_rf(project)
      end
    end
  end

  it "keeps the manifest untouched through the one-shot dedupe pass" do
    It.with_registry do |registry|
      registry.add("dep", "1.0.0", It.pkg("dep", "1.0.0"), {"index.js" => "1.0.0"})
      registry.add("dep", "1.2.0", It.pkg("dep", "1.2.0"), {"index.js" => "1.2.0"})
      registry.add("a", "1.0.0", It.pkg("a", "1.0.0", dependencies: {"dep" => "^1.0.0"}), {"index.js" => "a"})
      project = Path.new(Dir.tempdir, "zap-dedupe-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(project)
        File.write(project / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"a":"1.0.0"}}))
        File.write(project / ".npmrc", "registry=#{registry.base_url}/\n")
        config = Core::Config.new.copy_with(prefix: project.to_s, store_path: (project / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)
        before = File.read(project / "package.json")
        Commands::Install.run(config, ic.copy_with(dedupe: true, update_all: true, update_recursive: true, force_metadata_retrieval: true), raise_on_failure: true, reporter: Reporter::Null.new)
        File.read(project / "package.json").should eq(before)
      ensure
        FileUtils.rm_rf(project)
      end
    end
  end

  it "does not collapse versions during an update" do
    It.with_registry do |registry|
      registry.add("dep", "1.0.0", It.pkg("dep", "1.0.0"), {"index.js" => "1.0.0"})
      registry.add("dep", "1.2.0", It.pkg("dep", "1.2.0"), {"index.js" => "1.2.0"})
      registry.add("a", "1.0.0", It.pkg("a", "1.0.0", dependencies: {"dep" => "^1.0.0"}), {"index.js" => "a"})
      registry.add("b", "1.0.0", It.pkg("b", "1.0.0", dependencies: {"dep" => "^1.0.0"}), {"index.js" => "b"})
      project = Path.new(Dir.tempdir, "zap-dedupe-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(project)
        File.write(project / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"a":"1.0.0","b":"1.0.0"}}))
        File.write(project / ".npmrc", "registry=#{registry.base_url}/\n")
        config = Core::Config.new.copy_with(prefix: project.to_s, store_path: (project / "store").to_s, silent: true)
        Commands::Install.run(config, Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true), raise_on_failure: true, reporter: Reporter::Null.new)
        Commands::Install.run(config, Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true, update_all: true, update_recursive: true), raise_on_failure: true, reporter: Reporter::Null.new)
        lf = Data::Lockfile.new(project)
        lf.packages.keys.count { |k| k.starts_with?("dep@") }.should eq(1)
        lf.packages.keys.any? { |k| k == "dep@1.2.0" }.should be_true
      ensure
        FileUtils.rm_rf(project)
      end
    end
  end

  it "does not pick a prerelease for a stable range" do
    It.with_registry do |registry|
      registry.add("dep", "1.0.0-beta.1", It.pkg("dep", "1.0.0-beta.1"), {"index.js" => "beta"})
      registry.add("dep", "1.0.0", It.pkg("dep", "1.0.0"), {"index.js" => "1.0.0"})
      registry.add("a", "1.0.0", It.pkg("a", "1.0.0", dependencies: {"dep" => "^1.0.0"}), {"index.js" => "a"})
      registry.add("b", "1.0.0", It.pkg("b", "1.0.0", dependencies: {"dep" => "^1.0.0"}), {"index.js" => "b"})
      project = Path.new(Dir.tempdir, "zap-dedupe-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(project)
        File.write(project / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"a":"1.0.0","b":"1.0.0"}}))
        File.write(project / ".npmrc", "registry=#{registry.base_url}/\n")
        config = Core::Config.new.copy_with(prefix: project.to_s, store_path: (project / "store").to_s, silent: true)
        Commands::Install.run(config, Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true), raise_on_failure: true, reporter: Reporter::Null.new)
        lf = Data::Lockfile.new(project)
        lf.packages.keys.any? { |k| k == "dep@1.0.0-beta.1" }.should be_false
      ensure
        FileUtils.rm_rf(project)
      end
    end
  end

  it "dedupes with dev dependencies omitted" do
    It.with_registry do |registry|
      registry.add("dep", "1.0.0", It.pkg("dep", "1.0.0"), {"index.js" => "1.0.0"})
      registry.add("dep", "1.2.0", It.pkg("dep", "1.2.0"), {"index.js" => "1.2.0"})
      registry.add("a", "1.0.0", It.pkg("a", "1.0.0", dependencies: {"dep" => "^1.0.0"}), {"index.js" => "a"})
      registry.add("b", "1.0.0", It.pkg("b", "1.0.0", dependencies: {"dep" => "1.0.0"}), {"index.js" => "b"})
      project = Path.new(Dir.tempdir, "zap-dedupe-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(project)
        File.write(project / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"a":"1.0.0"},"devDependencies":{"b":"1.0.0"}}))
        File.write(project / ".npmrc", "registry=#{registry.base_url}/\n")
        config = Core::Config.new.copy_with(prefix: project.to_s, store_path: (project / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true, omit: [Commands::Install::Config::Omit::Dev])
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)
        # The dev-only subtree (b and its exact dep@1.0.0) is not installed;
        # the lockfile keeps the full graph (pnpm parity), the physical
        # tree only holds a's ^1.0.0.
        File.exists?(project / "node_modules/b").should be_false
        JSON.parse(File.read(project / "node_modules/dep/package.json"))["version"].as_s.should eq("1.2.0")
        dep_versions = Data::Lockfile.new(project).packages.keys.select { |k| k.starts_with?("dep@") }
        dep_versions.sort.should eq(["dep@1.0.0", "dep@1.2.0"])
        lock_before = File.read(project / "zap.lock")
        Commands::Install.run(config, ic.copy_with(dedupe: true, update_all: true, update_recursive: true, force_metadata_retrieval: true), raise_on_failure: true, reporter: Reporter::Null.new)
        # The one-shot keeps the same tree: nothing new, nothing churned.
        File.exists?(project / "node_modules/b").should be_false
        JSON.parse(File.read(project / "node_modules/dep/package.json"))["version"].as_s.should eq("1.2.0")
        File.read(project / "zap.lock").should eq(lock_before)
      ensure
        FileUtils.rm_rf(project)
      end
    end
  end

  it "does not dedupe onto versions locked only by omitted dependencies" do
    It.with_registry do |registry|
      registry.add("dep", "1.0.0", It.pkg("dep", "1.0.0"), {"index.js" => "1.0.0"})
      registry.add("dep", "1.2.0", It.pkg("dep", "1.2.0"), {"index.js" => "1.2.0"})
      registry.add("a", "1.0.0", It.pkg("a", "1.0.0", dependencies: {"dep" => "^1.0.0"}), {"index.js" => "a"})
      registry.add("b", "1.0.0", It.pkg("b", "1.0.0", dependencies: {"dep" => "1.0.0"}), {"index.js" => "b"})
      project = Path.new(Dir.tempdir, "zap-dedupe-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(project)
        File.write(project / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"a":"1.0.0"},"devDependencies":{"b":"1.0.0"}}))
        File.write(project / ".npmrc", "registry=#{registry.base_url}/\n")
        config = Core::Config.new.copy_with(prefix: project.to_s, store_path: (project / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true, omit: [Commands::Install::Config::Omit::Dev])
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)
        # a's ^1.0.0 must resolve fresh to the highest version: the locked
        # dep@1.0.0 is reachable only through the omitted dev edge and is
        # not a prefer-dedupe candidate.
        JSON.parse(File.read(project / "node_modules/dep/package.json"))["version"].as_s.should eq("1.2.0")
        # The lockfile still keeps the full graph.
        Data::Lockfile.new(project).packages.keys.select { |k| k.starts_with?("dep@") }.sort.should eq(["dep@1.0.0", "dep@1.2.0"])
      ensure
        FileUtils.rm_rf(project)
      end
    end
  end

  it "keeps declared ranges in the lockfile root through the one-shot dedupe pass" do
    It.with_registry do |registry|
      registry.add("dep", "1.0.0", It.pkg("dep", "1.0.0"), {"index.js" => "1.0.0"})
      registry.add("dep", "1.2.0", It.pkg("dep", "1.2.0"), {"index.js" => "1.2.0"})
      registry.add("a", "1.0.0", It.pkg("a", "1.0.0", dependencies: {"dep" => "^1.0.0"}), {"index.js" => "a"})
      project = Path.new(Dir.tempdir, "zap-dedupe-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(project)
        File.write(project / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"a":"1.0.0","dep":"^1.0.0"}}))
        File.write(project / ".npmrc", "registry=#{registry.base_url}/\n")
        config = Core::Config.new.copy_with(prefix: project.to_s, store_path: (project / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)
        Commands::Install.run(config, ic.copy_with(dedupe: true, update_all: true, update_recursive: true, force_metadata_retrieval: true), raise_on_failure: true, reporter: Reporter::Null.new)
        lockfile = Data::Lockfile.new(project)
        root = lockfile.roots["app"]
        root.try(&.dependencies).try(&.["dep"]?).should eq("^1.0.0")
        root.try(&.pinned_dependencies).try(&.["dep"]?).should eq("1.2.0")
        # The dedupe must not leave the lockfile churning: a subsequent
        # install writes an identical file.
        lock_after_dedupe = File.read(project / "zap.lock")
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)
        File.read(project / "zap.lock").should eq(lock_after_dedupe)
      ensure
        FileUtils.rm_rf(project)
      end
    end
  end

  # The prefer-dedupe option gates the one-shot pass too: with the option
  # off, `zap dedupe` degrades to a plain install — a diverged tree keeps
  # both pins (no collapse) and a stale pin is not silently upgraded to
  # the newest registry version.
  it "keeps diverged pins when prefer-dedupe is off through the one-shot pass" do
    It.with_registry do |registry|
      registry.add("dep", "1.0.0", It.pkg("dep", "1.0.0"), {"index.js" => "1.0.0"})
      registry.add("a", "1.0.0", It.pkg("a", "1.0.0", dependencies: {"dep" => "^1.0.0"}), {"index.js" => "a"})
      project = Path.new(Dir.tempdir, "zap-dedupe-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(project)
        File.write(project / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"a":"1.0.0"}}))
        File.write(project / ".npmrc", "registry=#{registry.base_url}/\n")
        config = Core::Config.new.copy_with(prefix: project.to_s, store_path: (project / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)
        # dep@1.2.0 and dep@1.3.0 appear later; b pulls in 1.2.0 while a
        # keeps its stale 1.0.0 pin. A fresh resolution of a's ^1.0.0 would
        # upgrade to 1.3.0, so the pass must not silently upgrade.
        registry.add("dep", "1.2.0", It.pkg("dep", "1.2.0"), {"index.js" => "1.2.0"})
        registry.add("dep", "1.3.0", It.pkg("dep", "1.3.0"), {"index.js" => "1.3.0"})
        registry.add("b", "1.0.0", It.pkg("b", "1.0.0", dependencies: {"dep" => "~1.2.0"}), {"index.js" => "b"})
        File.write(project / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"a":"1.0.0","b":"1.0.0"}}))
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)
        versions = ->(project : Path) { Data::Lockfile.new(project).packages.keys.select { |k| k.starts_with?("dep@") }.sort }
        versions.call(project).should eq(["dep@1.0.0", "dep@1.2.0"])
        lock_before = File.read(project / "zap.lock")
        # The exact config the CLI builds for `zap dedupe`.
        Commands::Install.run(config, ic.copy_with(dedupe: true, update_all: true, update_recursive: true, force_metadata_retrieval: true, prefer_dedupe: false), raise_on_failure: true, reporter: Reporter::Null.new)
        versions.call(project).should eq(["dep@1.0.0", "dep@1.2.0"])
        File.read(project / "zap.lock").should eq(lock_before)
      ensure
        FileUtils.rm_rf(project)
      end
    end
  end

  # The frozen guard must catch a dedupe that would update the lockfile
  # (CI parity): a collapsible divergence where the collapse changes pins.
  it "refuses to write a diverged lockfile under frozen-lockfile" do
    It.with_registry do |registry|
      registry.add("dep", "1.0.0", It.pkg("dep", "1.0.0"), {"index.js" => "1.0.0"})
      registry.add("a", "1.0.0", It.pkg("a", "1.0.0", dependencies: {"dep" => "^1.0.0"}), {"index.js" => "a"})
      project = Path.new(Dir.tempdir, "zap-dedupe-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(project)
        File.write(project / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"a":"1.0.0"}}))
        File.write(project / ".npmrc", "registry=#{registry.base_url}/\n")
        config = Core::Config.new.copy_with(prefix: project.to_s, store_path: (project / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)
        # dep@1.2.0 appears later; b pulls it in while a keeps its stale
        # 1.0.0 pin (its ^1.0.0 range accepts the collapse).
        registry.add("dep", "1.2.0", It.pkg("dep", "1.2.0"), {"index.js" => "1.2.0"})
        registry.add("b", "1.0.0", It.pkg("b", "1.0.0", dependencies: {"dep" => "~1.2.0"}), {"index.js" => "b"})
        File.write(project / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"a":"1.0.0","b":"1.0.0"}}))
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)
        Data::Lockfile.new(project).packages.keys.count { |k| k.starts_with?("dep@") }.should eq(2)
        raised = false
        begin
          Commands::Install.run(config, ic.copy_with(frozen_lockfile: true, dedupe: true, update_all: true, update_recursive: true, force_metadata_retrieval: true), raise_on_failure: true, reporter: Reporter::Null.new)
        rescue ex
          raised = true
          ex.message.not_nil!.should contain("frozen-lockfile")
        end
        raised.should be_true
        # The lockfile is untouched.
        Data::Lockfile.new(project).packages.keys.count { |k| k.starts_with?("dep@") }.should eq(2)
      ensure
        FileUtils.rm_rf(project)
      end
    end
  end
end

  # `zap add` inherits the dedupe: an added dependency whose range an
  # already-used version satisfies resolves to it instead of the newest
  # registry version, so the tree keeps a single copy. The saved
  # specifier keeps the declared range (npm parity).
  it "dedupes an added dependency against the versions in use" do
    It.with_registry do |registry|
      registry.add("dep", "1.0.0", It.pkg("dep", "1.0.0"), {"index.js" => "1.0.0"})
      registry.add("a", "1.0.0", It.pkg("a", "1.0.0", dependencies: {"dep" => "^1.0.0"}), {"index.js" => "a"})
      project = Path.new(Dir.tempdir, "zap-dedupe-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(project)
        File.write(project / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"a":"1.0.0"}}))
        File.write(project / ".npmrc", "registry=#{registry.base_url}/\n")
        config = Core::Config.new.copy_with(prefix: project.to_s, store_path: (project / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)
        # dep@1.2.0 appears later: a fresh resolution of ^1.0.0 would pick
        # it, but the dedupe keeps the version already in use (1.0.0).
        registry.add("dep", "1.2.0", It.pkg("dep", "1.2.0"), {"index.js" => "1.2.0"})
        Commands::Install.run(config, ic.copy_with(added_packages: ["dep@^1.0.0"]), raise_on_failure: true, reporter: Reporter::Null.new)
        manifest = JSON.parse(File.read(project / "package.json"))
        manifest["dependencies"]["dep"].as_s.should eq("^1.0.0")
        lockfile = Data::Lockfile.new(project)
        lockfile.packages.keys.count { |k| k.starts_with?("dep@") }.should eq(1)
        lockfile.packages.keys.find { |k| k.starts_with?("dep@") }.should eq("dep@1.0.0")
      ensure
        FileUtils.rm_rf(project)
      end
    end
  end

  # A file: dependency and a registry dependency of the same name coexist:
  # the dedupe candidates only come from registry entries, so the exotic
  # source never absorbs or is absorbed by the registry resolution.
  it "keeps a file dependency distinct from a registry dependency of the same name" do
    It.with_registry do |registry|
      registry.add("dep", "1.0.0", It.pkg("dep", "1.0.0"), {"index.js" => "1.0.0"})
      registry.add("dep", "1.2.0", It.pkg("dep", "1.2.0"), {"index.js" => "1.2.0"})
      registry.add("a", "1.0.0", It.pkg("a", "1.0.0", dependencies: {"dep" => "^1.0.0"}), {"index.js" => "a"})
      project = Path.new(Dir.tempdir, "zap-dedupe-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(project / "local-dep")
        File.write(project / "local-dep/package.json", %({"name":"dep","version":"2.0.0","main":"index.js"}))
        File.write(project / "local-dep/index.js", "local")
        File.write(project / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"a":"1.0.0","dep":"file:local-dep"}}))
        File.write(project / ".npmrc", "registry=#{registry.base_url}/\n")
        config = Core::Config.new.copy_with(prefix: project.to_s, store_path: (project / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)
        lockfile = Data::Lockfile.new(project)
        lockfile.packages.keys.count { |k| k.starts_with?("dep@") }.should eq(2)
        lockfile.packages.keys.any? { |k| k == "dep@1.2.0" }.should be_true
        JSON.parse(File.read(project / "node_modules/dep/package.json"))["version"].as_s.should eq("2.0.0")
        JSON.parse(File.read(project / "node_modules/a/node_modules/dep/package.json"))["version"].as_s.should eq("1.2.0")
        # The tree is stable: a reinstall does not churn.
        lock_after = File.read(project / "zap.lock")
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)
        File.read(project / "zap.lock").should eq(lock_after)
      ensure
        FileUtils.rm_rf(project)
      end
    end
  end

  # A package extension rewrites a dependency's declared range on every
  # visit of the one-shot pass. The subtree resolution pins the resolved
  # version afterwards, but a later parent's visit re-applied the extension
  # and reverted the pin to the range. The extension must apply once per
  # package per run. The mid chain schedules the second visit of ext after
  # the first visit's subtree pin (the pipeline runs fibers in spawn
  # order), so the revert is deterministic.
  it "keeps the pins when a package extension matches a shared package" do
    It.with_registry do |registry|
      registry.add("shared", "1.0.0", It.pkg("shared", "1.0.0"), {"index.js" => "1.0.0"})
      registry.add("shared", "1.2.0", It.pkg("shared", "1.2.0"), {"index.js" => "1.2.0"})
      registry.add("ext", "1.0.0", It.pkg("ext", "1.0.0", dependencies: {"shared" => "^1.0.0"}), {"index.js" => "e"})
      registry.add("mid1", "1.0.0", It.pkg("mid1", "1.0.0", dependencies: {"ext" => "^1.0.0"}), {"index.js" => "m1"})
      registry.add("mid2", "1.0.0", It.pkg("mid2", "1.0.0", dependencies: {"mid1" => "^1.0.0"}), {"index.js" => "m2"})
      registry.add("p1", "1.0.0", It.pkg("p1", "1.0.0", dependencies: {"ext" => "^1.0.0"}), {"index.js" => "1"})
      registry.add("p2", "1.0.0", It.pkg("p2", "1.0.0", dependencies: {"mid2" => "^1.0.0"}), {"index.js" => "2"})
      project = Path.new(Dir.tempdir, "zap-dedupe-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(project)
        File.write(project / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"p1":"1.0.0","p2":"1.0.0"},"zap":{"package_extensions":{"ext@1.0.0":{"dependencies":{"shared":">=1.0.0"}}}}}))
        File.write(project / ".npmrc", "registry=#{registry.base_url}/\n")
        config = Core::Config.new.copy_with(prefix: project.to_s, store_path: (project / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)
        Commands::Install.run(config, ic.copy_with(dedupe: true, update_all: true, update_recursive: true, force_metadata_retrieval: true), raise_on_failure: true, reporter: Reporter::Null.new)
        lockfile = Data::Lockfile.new(project)
        ext = lockfile.packages.values.find { |p| p.name == "ext" }
        ext.should_not be_nil
        ext.not_nil!.dependencies.should eq({"shared" => "1.2.0"})
      ensure
        FileUtils.rm_rf(project)
      end
    end
  end

  # The roots attribution on a workspace entry comes from the dependents
  # graph, which the one-shot builds on fresh objects. Registering the
  # dependents into those discarded objects dropped every parent after the
  # first, so a shared workspace package listed only one root and the
  # lockfile churned on the next install. The dependents must land on the
  # entry that survives in the lockfile.
  it "keeps the full roots attribution on shared workspace packages through the one-shot pass" do
    It.with_registry do |registry|
      ws_root = Path.new(Dir.tempdir, "zap-ws-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(ws_root / "packages/a")
        Dir.mkdir_p(ws_root / "packages/b")
        Dir.mkdir_p(ws_root / "packages/shared")
        File.write(ws_root / "package.json", %({"name":"ws","version":"1.0.0","workspaces":["packages/*"]}))
        File.write(ws_root / ".npmrc", "registry=#{registry.base_url}/\n")
        File.write(ws_root / "packages/shared/package.json", %({"name":"shared","version":"1.0.0","main":"index.js"}))
        File.write(ws_root / "packages/shared/index.js", "s")
        File.write(ws_root / "packages/a/package.json", %({"name":"a","version":"1.0.0","dependencies":{"shared":"workspace:*"}}))
        File.write(ws_root / "packages/b/package.json", %({"name":"b","version":"1.0.0","dependencies":{"shared":"workspace:*"}}))
        config = Core::Config.new.copy_with(prefix: ws_root.to_s, store_path: (ws_root / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)
        lockfile = Data::Lockfile.new(ws_root)
        shared = lockfile.packages.values.find { |p| p.name == "shared" }
        shared.should_not be_nil
        roots_after_install = shared.not_nil!.roots.to_a.sort
        roots_after_install.should contain("a")
        roots_after_install.should contain("b")
        Commands::Install.run(config, ic.copy_with(dedupe: true, update_all: true, update_recursive: true, force_metadata_retrieval: true), raise_on_failure: true, reporter: Reporter::Null.new)
        lockfile = Data::Lockfile.new(ws_root)
        shared = lockfile.packages.values.find { |p| p.name == "shared" }
        shared.should_not be_nil
        shared.not_nil!.roots.to_a.sort.should eq(roots_after_install)
        # No churn on the next install.
        lock_after_dedupe = File.read(ws_root / "zap.lock")
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)
        File.read(ws_root / "zap.lock").should eq(lock_after_dedupe)
      ensure
        FileUtils.rm_rf(ws_root)
      end
    end
  end

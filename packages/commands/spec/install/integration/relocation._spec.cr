require "../../../catalog/catalog"
require "./spec_helper"

# The classic writer removes stale physical copies as a byproduct of
# re-deriving each package's placement: a copy at the direct parent's
# node_modules is only valid while the package installs at the parent's
# own level. These specs pin the PHYSICAL layout, not just the lockfile,
# across hoisting alignments, partially-installed trees, and the other
# install strategies.

# Returns [{relative_package_dir, version}] of every physical copy of *name*.
private def physical_copies(project : Path, name : String) : Array({String, String})
  Dir.glob(project / "**/node_modules" / name / "package.json").map do |p|
    rel = Path.new(p).parent.to_s.gsub(project.to_s, "").lstrip('/')
    {rel, JSON.parse(File.read(p))["version"].as_s}
  end.sort
end

# A plain install; returns the project dir.
private def install_project(registry, package_json : String, strategy = Data::Package::InstallStrategy::Classic) : Path
  project = Path.new(Dir.tempdir, "zap-rel-#{Random::Secure.hex(4)}")
  Dir.mkdir_p(project)
  File.write(project / "package.json", package_json)
  File.write(project / ".npmrc", "registry=#{registry.base_url}/\n")
  config = Core::Config.new.copy_with(prefix: project.to_s, store_path: (project / "store").to_s, silent: true)
  ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true, strategy: strategy)
  Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)
  project
end

describe "classic relocation", tags: "integration" do
  it "keeps the physical tree stable on an up-to-date pass" do
    It.with_registry do |registry|
      registry.add("dep", "1.0.0", It.pkg("dep", "1.0.0"), {"index.js" => "1.0.0"})
      registry.add("dep", "1.2.0", It.pkg("dep", "1.2.0"), {"index.js" => "1.2.0"})
      registry.add("a", "1.0.0", It.pkg("a", "1.0.0", dependencies: {"dep" => "^1.0.0"}), {"index.js" => "a"})
      registry.add("b", "1.0.0", It.pkg("b", "1.0.0", dependencies: {"dep" => "~1.2.0"}), {"index.js" => "b"})

      project = install_project(registry, %({"name":"app","version":"1.0.0","dependencies":{"a":"1.0.0","b":"1.0.0"}}))
      begin
        # The first install with prefer-dedupe on: both ranges collapse to
        # 1.2.0, hoisted at the root.
        physical_copies(project, "dep").should eq([{"node_modules/dep", "1.2.0"}])

        # The up-to-date pass re-derives the same placement: nothing moves.
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true)
        config = Core::Config.new.copy_with(prefix: project.to_s, store_path: (project / "store").to_s, silent: true)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)
        physical_copies(project, "dep").should eq([{"node_modules/dep", "1.2.0"}])
      ensure
        FileUtils.rm_rf(project)
      end
    end
  end

  it "removes a sibling subtree's moot nested copy regardless of the resolution order" do
    It.with_registry do |registry|
      registry.add("dep", "1.0.0", It.pkg("dep", "1.0.0"), {"index.js" => "1.0.0"})
      registry.add("a", "1.0.0", It.pkg("a", "1.0.0", dependencies: {"dep" => "^1.0.0"}), {"index.js" => "a"})
      project = Path.new(Dir.tempdir, "zap-rel-#{Random::Secure.hex(4)}")
      Dir.mkdir_p(project)
      File.write(project / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"a":"1.0.0"}}))
      File.write(project / ".npmrc", "registry=#{registry.base_url}/\n")
      config = Core::Config.new.copy_with(prefix: project.to_s, store_path: (project / "store").to_s, silent: true)
      ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true)
      begin
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)
        registry.add("dep", "1.2.0", It.pkg("dep", "1.2.0"), {"index.js" => "1.2.0"})
        registry.add("b", "1.0.0", It.pkg("b", "1.0.0", dependencies: {"dep" => "~1.2.0"}), {"index.js" => "b"})
        # `b` is declared first: its dep resolves before `a`'s.
        File.write(project / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"b":"1.0.0","a":"1.0.0"}}))
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)
        physical_copies(project, "dep").should eq([{"node_modules/b/node_modules/dep", "1.2.0"}, {"node_modules/dep", "1.0.0"}])

        # The dedupe collapses both to 1.2.0. Whichever subtree resolves
        # first lands at the root; the other's nested copy is moot and the
        # writer removes it in the same pass.
        ic2 = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true, dedupe: true, update_all: true, update_recursive: true, force_metadata_retrieval: true)
        Commands::Install.run(config, ic2, raise_on_failure: true, reporter: Reporter::Null.new)
        physical_copies(project, "dep").should eq([{"node_modules/dep", "1.2.0"}])
        File.exists?(project / "node_modules/b/node_modules").should be_false
      ensure
        FileUtils.rm_rf(project)
      end
    end
  end

  it "removes a mid-tree copy when its subtree disappears" do
    It.with_registry do |registry|
      registry.add("dep", "0.9.0", It.pkg("dep", "0.9.0"), {"index.js" => "0.9.0"})
      registry.add("dep", "1.0.0", It.pkg("dep", "1.0.0"), {"index.js" => "1.0.0"})
      registry.add("x", "1.0.0", It.pkg("x", "1.0.0", dependencies: {"dep" => "^0.9.0"}), {"index.js" => "x"})
      registry.add("a", "1.0.0", It.pkg("a", "1.0.0", dependencies: {"dep" => "^1.0.0"}), {"index.js" => "a"})

      project = Path.new(Dir.tempdir, "zap-rel-#{Random::Secure.hex(4)}")
      Dir.mkdir_p(project)
      File.write(project / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"x":"1.0.0","a":"1.0.0"}}))
      File.write(project / ".npmrc", "registry=#{registry.base_url}/\n")
      config = Core::Config.new.copy_with(prefix: project.to_s, store_path: (project / "store").to_s, silent: true)
      ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true)
      begin
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)
        # a's dep lands at the root; x's dep stays at x's (mid-tree) level
        # because the root holds an incompatible version.
        physical_copies(project, "dep").should eq([{"node_modules/dep", "1.0.0"}, {"node_modules/x/node_modules/dep", "0.9.0"}])

        # Removing x drops its subtree (the mid-tree copy included) in the
        # same pass.
        File.write(project / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"a":"1.0.0"}}))
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)
        physical_copies(project, "dep").should eq([{"node_modules/dep", "1.0.0"}])
      ensure
        FileUtils.rm_rf(project)
      end
    end
  end

  it "keeps a peer dependency's tree stable on reinstalls" do
    It.with_registry do |registry|
      registry.add("dep", "1.0.0", It.pkg("dep", "1.0.0", peer_dependencies: {"a" => "^1.0.0"}), {"index.js" => "1.0.0"})
      registry.add("a", "1.0.0", It.pkg("a", "1.0.0", dependencies: {"dep" => "^1.0.0"}), {"index.js" => "a"})

      project = install_project(registry, %({"name":"app","version":"1.0.0","dependencies":{"a":"1.0.0"}}))
      begin
        # The dep is hoisted at the root; its peer `a` resolves next to it.
        physical_copies(project, "dep").should eq([{"node_modules/dep", "1.0.0"}])

        # Reinstalls leave the peer-satisfying tree in place.
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true)
        config = Core::Config.new.copy_with(prefix: project.to_s, store_path: (project / "store").to_s, silent: true)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)
        physical_copies(project, "dep").should eq([{"node_modules/dep", "1.0.0"}])
      ensure
        FileUtils.rm_rf(project)
      end
    end
  end

  it "keeps a nohoist workspace copy nested" do
    It.with_registry do |registry|
      registry.add("dep", "1.0.0", It.pkg("dep", "1.0.0"), {"index.js" => "1.0.0"})

      ws_root = Path.new(Dir.tempdir, "zap-rel-#{Random::Secure.hex(4)}")
      Dir.mkdir_p(ws_root / "packages" / "a")
      File.write(ws_root / "package.json", %({"name":"ws","version":"1.0.0","workspaces":{"packages":["packages/*"],"nohoist":["**/dep"]}}))
      File.write(ws_root / ".npmrc", "registry=#{registry.base_url}/\n")
      File.write(ws_root / "packages/a/package.json", %({"name":"a","version":"1.0.0","dependencies":{"dep":"1.0.0"}}))
      config = Core::Config.new.copy_with(prefix: ws_root.to_s, store_path: (ws_root / "store").to_s, silent: true)
      ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true)
      begin
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)
        physical_copies(ws_root, "dep").should eq([{"packages/a/node_modules/dep", "1.0.0"}])

        # A reinstall keeps the nohoist copy.
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)
        physical_copies(ws_root, "dep").should eq([{"packages/a/node_modules/dep", "1.0.0"}])
      ensure
        FileUtils.rm_rf(ws_root)
      end
    end
  end

  it "sweeps a partially-installed stale copy left on disk" do
    It.with_registry do |registry|
      registry.add("dep", "1.0.0", It.pkg("dep", "1.0.0"), {"index.js" => "1.0.0"})
      registry.add("a", "1.0.0", It.pkg("a", "1.0.0", dependencies: {"dep" => "^1.0.0"}), {"index.js" => "a"})
      project = Path.new(Dir.tempdir, "zap-rel-#{Random::Secure.hex(4)}")
      Dir.mkdir_p(project)
      File.write(project / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"a":"1.0.0"}}))
      File.write(project / ".npmrc", "registry=#{registry.base_url}/\n")
      config = Core::Config.new.copy_with(prefix: project.to_s, store_path: (project / "store").to_s, silent: true)
      ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true)
      begin
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)
        registry.add("dep", "1.2.0", It.pkg("dep", "1.2.0"), {"index.js" => "1.2.0"})
        registry.add("b", "1.0.0", It.pkg("b", "1.0.0", dependencies: {"dep" => "~1.2.0"}), {"index.js" => "b"})
        File.write(project / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"a":"1.0.0","b":"1.0.0"}}))
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)
        physical_copies(project, "dep").should eq([{"node_modules/b/node_modules/dep", "1.2.0"}, {"node_modules/dep", "1.0.0"}])

        # Simulate an interrupted pass: a stale copy without a matching
        # installed-state entry, plus an orphan nested directory.
        stale = project / "node_modules/b/node_modules/dep"
        FileUtils.rm_rf(stale)
        Dir.mkdir_p(stale)
        File.write(stale / "package.json", %({"name":"dep","version":"0.5.0"}))
        Dir.mkdir_p(project / "node_modules/b/node_modules/ghost")
        File.write(project / "node_modules/b/node_modules/ghost/package.json", %({"name":"ghost","version":"1.0.0"}))

        # The writer sweeps b's nested copy when its dep lands at the root.
        ic2 = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true, dedupe: true, update_all: true, update_recursive: true, force_metadata_retrieval: true)
        Commands::Install.run(config, ic2, raise_on_failure: true, reporter: Reporter::Null.new)
        physical_copies(project, "dep").should eq([{"node_modules/dep", "1.2.0"}])
      ensure
        FileUtils.rm_rf(project)
      end
    end
  end

  it "replaces a copy in place when its version changes" do
    It.with_registry do |registry|
      registry.add("dep", "1.0.0", It.pkg("dep", "1.0.0"), {"index.js" => "1.0.0"})
      registry.add("a", "1.0.0", It.pkg("a", "1.0.0", dependencies: {"dep" => "^1.0.0"}), {"index.js" => "a"})

      project = Path.new(Dir.tempdir, "zap-rel-#{Random::Secure.hex(4)}")
      Dir.mkdir_p(project)
      File.write(project / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"a":"1.0.0"}}))
      File.write(project / ".npmrc", "registry=#{registry.base_url}/\n")
      config = Core::Config.new.copy_with(prefix: project.to_s, store_path: (project / "store").to_s, silent: true)
      ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true)
      begin
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)
        physical_copies(project, "dep").should eq([{"node_modules/dep", "1.0.0"}])

        # The update bumps the range to 1.2.0 at the same location: the
        # copy is replaced in place (key mismatch -> re-link), not removed.
        registry.add("dep", "1.2.0", It.pkg("dep", "1.2.0"), {"index.js" => "1.2.0"})
        ic2 = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true, update_all: true, update_recursive: true)
        Commands::Install.run(config, ic2, raise_on_failure: true, reporter: Reporter::Null.new)
        physical_copies(project, "dep").should eq([{"node_modules/dep", "1.2.0"}])
      ensure
        FileUtils.rm_rf(project)
      end
    end
  end

  it "keeps the tree stable on a subsequent dedupe pass" do
    It.with_registry do |registry|
      registry.add("dep", "1.0.0", It.pkg("dep", "1.0.0"), {"index.js" => "1.0.0"})
      registry.add("a", "1.0.0", It.pkg("a", "1.0.0", dependencies: {"dep" => "^1.0.0"}), {"index.js" => "a"})
      project = Path.new(Dir.tempdir, "zap-rel-#{Random::Secure.hex(4)}")
      Dir.mkdir_p(project)
      File.write(project / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"a":"1.0.0"}}))
      File.write(project / ".npmrc", "registry=#{registry.base_url}/\n")
      config = Core::Config.new.copy_with(prefix: project.to_s, store_path: (project / "store").to_s, silent: true)
      ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true)
      begin
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)
        registry.add("dep", "1.2.0", It.pkg("dep", "1.2.0"), {"index.js" => "1.2.0"})
        registry.add("b", "1.0.0", It.pkg("b", "1.0.0", dependencies: {"dep" => "~1.2.0"}), {"index.js" => "b"})
        File.write(project / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"a":"1.0.0","b":"1.0.0"}}))
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)
        ic2 = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true, dedupe: true, update_all: true, update_recursive: true, force_metadata_retrieval: true)
        Commands::Install.run(config, ic2, raise_on_failure: true, reporter: Reporter::Null.new)
        physical_copies(project, "dep").should eq([{"node_modules/dep", "1.2.0"}])

        # A second dedupe pass is a no-op on the physical tree.
        Commands::Install.run(config, ic2, raise_on_failure: true, reporter: Reporter::Null.new)
        physical_copies(project, "dep").should eq([{"node_modules/dep", "1.2.0"}])
      ensure
        FileUtils.rm_rf(project)
      end
    end
  end

  # The non-hoisting strategies have their own linkers and store layouts;
  # the dedupe must leave their trees stable across the following pass.
  ["isolated", "pnp"].each do |strategy_name|
    it "keeps the deduped tree stable on reinstalls with the #{strategy_name} strategy" do
      strategy = strategy_name == "pnp" ? Data::Package::InstallStrategy::Pnp : Data::Package::InstallStrategy::Isolated
      It.with_registry do |registry|
        registry.add("dep", "1.0.0", It.pkg("dep", "1.0.0"), {"index.js" => "1.0.0"})
        registry.add("a", "1.0.0", It.pkg("a", "1.0.0", dependencies: {"dep" => "^1.0.0"}), {"index.js" => "a"})
        project = Path.new(Dir.tempdir, "zap-rel-#{Random::Secure.hex(4)}")
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
          lockfile.packages.keys.select { |k| k.starts_with?("dep@") }.should eq(["dep@1.2.0"])

          # The following plain install (and another dedupe) is stable.
          Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)
          Commands::Install.run(config, ic2, raise_on_failure: true, reporter: Reporter::Null.new)
          lockfile = Data::Lockfile.new(project)
          lockfile.packages.keys.select { |k| k.starts_with?("dep@") }.should eq(["dep@1.2.0"])
        ensure
          FileUtils.rm_rf(project)
        end
      end
    end
  end

  # Partial node_modules deletion (a whole subtree or a nested copy
  # disappears between runs): the reinstall must rebuild exactly the
  # missing pieces from the lockfile and leave the rest untouched.
  it "rebuilds a partially-deleted subtree on reinstall" do
    It.with_registry do |registry|
      registry.add("dep", "1.0.0", It.pkg("dep", "1.0.0"), {"index.js" => "1.0.0"})
      registry.add("a", "1.0.0", It.pkg("a", "1.0.0", dependencies: {"dep" => "^1.0.0"}), {"index.js" => "a"})
      project = Path.new(Dir.tempdir, "zap-rel-#{Random::Secure.hex(4)}")
      Dir.mkdir_p(project)
      File.write(project / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"a":"1.0.0"}}))
      File.write(project / ".npmrc", "registry=#{registry.base_url}/\n")
      config = Core::Config.new.copy_with(prefix: project.to_s, store_path: (project / "store").to_s, silent: true)
      ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true)
      begin
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)
        # dep@1.2.0 appears later; b pulls it in while a keeps its stale
        # 1.0.0 pin, so the tree genuinely holds both versions.
        registry.add("dep", "1.2.0", It.pkg("dep", "1.2.0"), {"index.js" => "1.2.0"})
        registry.add("b", "1.0.0", It.pkg("b", "1.0.0", dependencies: {"dep" => "~1.2.0"}), {"index.js" => "b"})
        File.write(project / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"a":"1.0.0","b":"1.0.0"}}))
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)
        physical_copies(project, "dep").should eq([{"node_modules/b/node_modules/dep", "1.2.0"}, {"node_modules/dep", "1.0.0"}])
        lock_after_install = File.read(project / "zap.lock")

        # Delete b's whole subtree, then reinstall: b and its nested copy
        # come back, nothing else moves.
        FileUtils.rm_rf(project / "node_modules/b")
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)
        physical_copies(project, "dep").should eq([{"node_modules/b/node_modules/dep", "1.2.0"}, {"node_modules/dep", "1.0.0"}])
        File.read(project / "zap.lock").should eq(lock_after_install)

        # Delete only the nested copy, then reinstall: it is re-linked in
        # place without touching the hoisted version.
        FileUtils.rm_rf(project / "node_modules/b/node_modules/dep")
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)
        physical_copies(project, "dep").should eq([{"node_modules/b/node_modules/dep", "1.2.0"}, {"node_modules/dep", "1.0.0"}])
        File.read(project / "zap.lock").should eq(lock_after_install)
      ensure
        FileUtils.rm_rf(project)
      end
    end
  end
end

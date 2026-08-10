require "./spec_helper"


# The same repository shapes installed with every strategy, mirroring yarn's
# linker matrix (pnp / pnpm / node-modules).
describe "install strategies", tags: "integration" do
  it "installs with the isolated strategy" do
    It.with_registry do |registry|
      registry.add("b", "1.0.0", It.pkg("b", "1.0.0"), {"index.js" => "b"})
      registry.add("a", "1.0.0", It.pkg("a", "1.0.0", dependencies: {"b" => "1.0.0"}), {"index.js" => "a"})

      ic = Commands::Install::Config.new.copy_with(strategy: Data::Package::InstallStrategy::Isolated)
      It.install_project(registry, %({"name":"app","version":"1.0.0","dependencies":{"a":"1.0.0"}}), install_config: ic) do |project|
        # Virtual store with the packages, top-level symlinks
        File.symlink?(project / "node_modules/a").should be_true
        Dir.exists?(project / "node_modules/.store").should be_true
        # The transitive dependency lives in the virtual store
        Dir.glob(project / "node_modules/.store/b@*/node_modules/b").size.should eq(1)
      end
    end
  end

  it "installs with the pnp strategy" do
    It.with_registry do |registry|
      registry.add("b", "1.0.0", It.pkg("b", "1.0.0"), {"index.js" => "b"})
      registry.add("a", "1.0.0", It.pkg("a", "1.0.0", dependencies: {"b" => "1.0.0"}), {"index.js" => "a"})

      ic = Commands::Install::Config.new.copy_with(strategy: Data::Package::InstallStrategy::Pnp)
      It.install_project(registry, %({"name":"app","version":"1.0.0","dependencies":{"a":"1.0.0"}}), install_config: ic) do |project|
        # No node_modules for the packages; the plug'n'play manifest holds the tree
        File.exists?(project / ".pnp.data.json").should be_true
        File.exists?(project / ".pnp.cjs").should be_true
        File.exists?(project / "node_modules/a").should be_false
      end
    end
  end

  it "resolves peers with the isolated strategy" do
    It.with_registry do |registry|
      registry.add("fallback-peer-deps", "1.0.0",
        It.pkg("fallback-peer-deps", "1.0.0", dependencies: {"no-deps" => "2.0.0"}, peer_dependencies: {"no-deps" => "*"}),
        {"index.js" => "fpd"})
      registry.add("no-deps", "1.0.0", It.pkg("no-deps", "1.0.0"), {"index.js" => "1.0.0"})
      registry.add("no-deps", "2.0.0", It.pkg("no-deps", "2.0.0"), {"index.js" => "2.0.0"})

      ic = Commands::Install::Config.new.copy_with(strategy: Data::Package::InstallStrategy::Isolated)
      It.install_project(
        registry,
        %({"name":"app","version":"1.0.0","dependencies":{"fallback-peer-deps":"1.0.0","no-deps":"1.0.0"}}),
        install_config: ic
      ) do |project|
        # The peer (1.0.0) wins over the regular dependency (2.0.0)
        target = File.realpath(project / "node_modules/no-deps")
        File.read(Path.new(target) / "index.js").should eq("1.0.0")
      end
    end
  end
end

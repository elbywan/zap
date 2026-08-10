require "./spec_helper"


# Peer dependency semantics, mirroring yarn's pkg-tests fixtures
# (fallback-peer-deps, peer-deps, provides-peer-deps, peer-deps-lvl0/1/2).
describe "peer dependencies", tags: "integration" do
  it "resolves peers from the top level" do
    It.with_registry do |registry|
      registry.add("peer-deps", "1.0.0", It.pkg("peer-deps", "1.0.0", peer_dependencies: {"no-deps" => "*"}), {"index.js" => "pd"})
      registry.add("no-deps", "1.0.0", It.pkg("no-deps", "1.0.0"), {"index.js" => "1.0.0"})

      It.install_project(
        registry,
        %({"name":"app","version":"1.0.0","dependencies":{"peer-deps":"1.0.0","no-deps":"1.0.0"}})
      ) do |project|
        File.exists?(project / "node_modules/peer-deps/index.js").should be_true
        File.read(project / "node_modules/no-deps/index.js").should eq("1.0.0")
      end
    end
  end

  it "resolves peers from within a dependency" do
    It.with_registry do |registry|
      registry.add("peer-deps", "1.0.0", It.pkg("peer-deps", "1.0.0", peer_dependencies: {"no-deps" => "*"}), {"index.js" => "pd"})
      registry.add("no-deps", "1.0.0", It.pkg("no-deps", "1.0.0"), {"index.js" => "1.0.0"})
      registry.add("provides-peer-deps", "1.0.0",
        It.pkg("provides-peer-deps", "1.0.0", dependencies: {"peer-deps" => "1.0.0", "no-deps" => "1.0.0"}),
        {"index.js" => "ppd"})

      It.install_project(registry, %({"name":"app","version":"1.0.0","dependencies":{"provides-peer-deps":"1.0.0"}})) do |project|
        File.exists?(project / "node_modules/peer-deps/index.js").should be_true
        File.read(project / "node_modules/no-deps/index.js").should eq("1.0.0")
      end
    end
  end

  it "resolves peers two levels deep" do
    It.with_registry do |registry|
      registry.add("no-deps", "1.0.0", It.pkg("no-deps", "1.0.0"), {"index.js" => "1.0.0"})
      registry.add("peer-deps-lvl0", "1.0.0",
        It.pkg("peer-deps-lvl0", "1.0.0", dependencies: {"no-deps" => "1.0.0", "peer-deps-lvl1" => "1.0.0"}),
        {"index.js" => "lvl0"})
      registry.add("peer-deps-lvl1", "1.0.0",
        It.pkg("peer-deps-lvl1", "1.0.0", dependencies: {"peer-deps-lvl2" => "1.0.0"}, peer_dependencies: {"no-deps" => "*"}),
        {"index.js" => "lvl1"})
      registry.add("peer-deps-lvl2", "1.0.0",
        It.pkg("peer-deps-lvl2", "1.0.0", peer_dependencies: {"no-deps" => "*"}),
        {"index.js" => "lvl2"})

      It.install_project(registry, %({"name":"app","version":"1.0.0","dependencies":{"peer-deps-lvl0":"1.0.0"}})) do |project|
        File.exists?(project / "node_modules/peer-deps-lvl0/index.js").should be_true
        File.exists?(project / "node_modules/peer-deps-lvl1/index.js").should be_true
        File.exists?(project / "node_modules/peer-deps-lvl2/index.js").should be_true
        File.read(project / "node_modules/no-deps/index.js").should eq("1.0.0")
      end
    end
  end

  it "prefers the peer over the same regular dependency when the peer is met" do
    It.with_registry do |registry|
      # fallback-peer-deps declares a regular dep on no-deps@2 AND a peer on no-deps@*
      registry.add("fallback-peer-deps", "1.0.0",
        It.pkg("fallback-peer-deps", "1.0.0", dependencies: {"no-deps" => "2.0.0"}, peer_dependencies: {"no-deps" => "*"}),
        {"index.js" => "fpd"})
      registry.add("no-deps", "1.0.0", It.pkg("no-deps", "1.0.0"), {"index.js" => "1.0.0"})
      registry.add("no-deps", "2.0.0", It.pkg("no-deps", "2.0.0"), {"index.js" => "2.0.0"})

      It.install_project(
        registry,
        %({"name":"app","version":"1.0.0","dependencies":{"fallback-peer-deps":"1.0.0","no-deps":"1.0.0"}})
      ) do |project|
        # The peer (from the root) wins: no-deps@2 is not installed under the package
        File.read(project / "node_modules/no-deps/index.js").should eq("1.0.0")
        File.exists?(project / "node_modules/fallback-peer-deps/node_modules/no-deps").should be_false
      end
    end
  end

  it "falls back to the regular dependency when the peer is unmet" do
    It.with_registry do |registry|
      registry.add("fallback-peer-deps", "1.0.0",
        It.pkg("fallback-peer-deps", "1.0.0", dependencies: {"no-deps" => "2.0.0"}, peer_dependencies: {"no-deps" => "*"}),
        {"index.js" => "fpd"})
      registry.add("no-deps", "2.0.0", It.pkg("no-deps", "2.0.0"), {"index.js" => "2.0.0"})

      It.install_project(registry, %({"name":"app","version":"1.0.0","dependencies":{"fallback-peer-deps":"1.0.0"}})) do |project|
        # No ancestor provides the peer, so the regular dependency is installed
        # instead and resolves from the tree (hoisted to the root here)
        File.read(project / "node_modules/no-deps/index.js").should eq("2.0.0")
      end
    end
  end
end

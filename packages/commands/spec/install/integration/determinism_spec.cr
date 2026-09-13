require "./spec_helper"

# Deterministic resolution: two sequential installs of the same
# conflict-heavy graph must produce identical trees.
#
# The graphs are generated deterministically and only depend on
# higher-numbered packages (a cycle with conflicting ranges would nest
# copies forever). The interesting part is version selection: with several
# satisfying versions, prefer-dedupe used to consult the resolutions of
# the current run — which land in fiber-completion order — so two installs
# of the same inputs could differ (see the dedupe_candidate snapshot in
# Protocol::Registry::Resolver).
DETERMINISM_NAMES    = ["p0", "p1", "p2", "p3", "p4", "p5"]
DETERMINISM_VERSIONS = ["1.0.0", "1.1.0", "2.0.0"]
DETERMINISM_RANGES   = ["^1.0.0", "~1.0.0", "1.0.0", "^2.0.0", "*", ">=1.0.0 <2.1.0"]

def determinism_tree(root : Path) : Array(String)
  entries = [] of String
  return entries unless Dir.exists?(root)
  Dir.glob(File.join(root.to_s, "**", "*"), match_hidden: true) do |path|
    rel = path[(root.to_s.size + 1)..]
    next if rel.empty?
    # The installed state and the fingerprint serialise in walk order and
    # hash absolute paths (the temp directory differs per run).
    next if rel == ".zap-state" || rel == ".zap-fingerprint"
    if File.symlink?(path)
      entries << "#{rel} -> #{File.readlink(path)}"
    elsif File.file?(path)
      entries << "#{rel} #{File.size(path)} #{Digest::MD5.hexdigest(File.read(path))}"
    end
  end
  entries.sort!
end

describe "install determinism", tags: "integration" do
  it "resolves the same graph the same way on repeated installs" do
    It.with_registry do |registry|
      (0...8).each do |seed|
        rng = Random.new(seed.to_u64 * 2654435761_u64)
        DETERMINISM_NAMES.each do |name|
          DETERMINISM_VERSIONS.each do |version|
            deps = {} of String => String
            peers = {} of String => String
            DETERMINISM_NAMES.each do |other|
              next if other <= name
              deps[other] = DETERMINISM_RANGES.sample(rng) if rng.rand(100) < 45
              peers[other] = DETERMINISM_RANGES.sample(rng) if rng.rand(100) < 20
            end
            registry.add(name, version,
              It.pkg(name, version, dependencies: deps, peer_dependencies: peers),
              {"index.js" => "#{name}@#{version}", "lib/data.txt" => "#{name}@#{version}-data"})
          end
        end
        root_deps = {} of String => String
        DETERMINISM_NAMES.each { |name| root_deps[name] = DETERMINISM_RANGES.sample(rng) if rng.rand(100) < 60 }
        next if root_deps.empty?
        package_json = %({"name":"app","version":"1.0.0","dependencies":#{root_deps.to_json}})

        trees = [] of Array(String)
        2.times do
          tmpdir = Path.new(Dir.tempdir, "zap-determinism-#{Random::Secure.hex(4)}")
          begin
            Dir.mkdir_p(tmpdir)
            File.write(tmpdir / "package.json", package_json)
            File.write(tmpdir / ".npmrc", "registry=#{registry.base_url}/\n")
            config = Core::Config.new.copy_with(prefix: tmpdir.to_s, store_path: (tmpdir / "store").to_s, silent: true)
            ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: false)
            Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)
            trees << determinism_tree(tmpdir / "node_modules")
          ensure
            FileUtils.rm_rf(tmpdir)
          end
        end

        first, second = trees[0], trees[1]
        unless first == second
          differing = (first - second) + (second - first)
          fail "seed #{seed} resolved differently between two installs: #{differing.first(4).inspect}"
        end
      end
    end
  end
end

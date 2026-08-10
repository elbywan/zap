require "./spec_helper"

# Ports of yarn berry's pnp tests (pkg-tests-specs/sources/pnp.js), run
# against zap's .pnp.cjs runtime via node's --require hook: peer
# virtualization, self-requires and top-level fallback semantics.

# Runs node with the project's pnp runtime injected and returns the output.
def pnp_source(project : Path, code : String) : {Bool, String, String}
  stdout_io = IO::Memory.new
  err_io = IO::Memory.new
  status = Process.run("node", ["-e", code], chdir: project.to_s, output: stdout_io, error: err_io,
    env: {"NODE_OPTIONS" => "--require #{project}/.pnp.cjs"})
  {status.success?, stdout_io.to_s, err_io.to_s}
end

describe "berry pnp ports", tags: "integration" do
  it "gives two identical packages with different peers different instances" do
    It.with_registry do |registry|
      registry.add("no-deps", "1.0.0", It.pkg("no-deps", "1.0.0"), {"index.js" => "module.exports = {name: 'no-deps', version: '1.0.0'}"})
      registry.add("no-deps", "2.0.0", It.pkg("no-deps", "2.0.0"), {"index.js" => "module.exports = {name: 'no-deps', version: '2.0.0'}"})
      registry.add("peer-deps", "1.0.0", It.pkg("peer-deps", "1.0.0", peer_dependencies: {"no-deps" => "*"}),
        {"index.js" => "module.exports = {name: 'peer-deps', version: '1.0.0', peerDependencies: {'no-deps': require('no-deps')}}"})
      registry.add("provides-peer-deps-1-0-0", "1.0.0",
        It.pkg("provides-peer-deps-1-0-0", "1.0.0", dependencies: {"peer-deps" => "1.0.0", "no-deps" => "1.0.0"}),
        {"index.js" => "module.exports = {name: 'provides-peer-deps-1-0-0', version: '1.0.0', dependencies: {'peer-deps': require('peer-deps'), 'no-deps': require('no-deps')}}"})
      registry.add("provides-peer-deps-2-0-0", "1.0.0",
        It.pkg("provides-peer-deps-2-0-0", "1.0.0", dependencies: {"peer-deps" => "1.0.0", "no-deps" => "2.0.0"}),
        {"index.js" => "module.exports = {name: 'provides-peer-deps-2-0-0', version: '1.0.0', dependencies: {'peer-deps': require('peer-deps'), 'no-deps': require('no-deps')}}"})

      ic = Commands::Install::Config.new.copy_with(strategy: Data::Package::InstallStrategy::Pnp)
      It.install_project(registry, %({"name":"app","version":"1.0.0","dependencies":{"provides-peer-deps-1-0-0":"1.0.0","provides-peer-deps-2-0-0":"1.0.0"}}), install_config: ic) do |project|
        ok, stdout, err = pnp_source(project, "const a = require('provides-peer-deps-1-0-0'); const b = require('provides-peer-deps-2-0-0'); process.stdout.write(JSON.stringify({peerDepsDifferent: a.dependencies['peer-deps'] !== b.dependencies['peer-deps'], aPeer: a.dependencies['peer-deps'].peerDependencies['no-deps'].version, bPeer: b.dependencies['peer-deps'].peerDependencies['no-deps'].version, aSelf: a.dependencies['no-deps'].version, bSelf: b.dependencies['no-deps'].version}))")
        ok.should be_true, "pnp runtime error: #{err}"
        JSON.parse(stdout).should eq(JSON.parse(%({"peerDepsDifferent":true,"aPeer":"1.0.0","bPeer":"2.0.0","aSelf":"1.0.0","bSelf":"2.0.0"})))
      end
    end
  end

  it "lets packages require themselves" do
    It.with_registry do |registry|
      registry.add("various-requires", "1.0.0", It.pkg("various-requires", "1.0.0"),
        {"index.js" => "module.exports = {name: 'various-requires', version: '1.0.0'}",
         "self.js" => "module.exports = require('various-requires')"})

      ic = Commands::Install::Config.new.copy_with(strategy: Data::Package::InstallStrategy::Pnp)
      It.install_project(registry, %({"name":"app","version":"1.0.0","dependencies":{"various-requires":"1.0.0"}}), install_config: ic) do |project|
        ok, stdout, err = pnp_source(project, "process.stdout.write(JSON.stringify(require('various-requires/self') === require('various-requires')))")
        ok.should be_true, "pnp runtime error: #{err}"
        stdout.should eq("true")
      end
    end
  end

  it "does not fall back to undeclared top-level dependencies (stricter than berry)" do
    It.with_registry do |registry|
      registry.add("various-requires", "1.0.0", It.pkg("various-requires", "1.0.0"),
        {"index.js" => "module.exports = require('no-deps')",
         "invalid-require.js" => "module.exports = require('no-deps')"})
      registry.add("no-deps", "1.0.0", It.pkg("no-deps", "1.0.0"), {"index.js" => "module.exports = {name: 'no-deps', version: '1.0.0'}"})

      ic = Commands::Install::Config.new.copy_with(strategy: Data::Package::InstallStrategy::Pnp)
      It.install_project(registry, %({"name":"app","version":"1.0.0","dependencies":{"various-requires":"1.0.0","no-deps":"1.0.0"}}), install_config: ic) do |project|
        # berry falls back to the top-level dependency here; zap's runtime
        # deliberately rejects undeclared requires
        ok, _stdout, err = pnp_source(project, "process.stdout.write(JSON.stringify(require('various-requires/invalid-require')))")
        ok.should be_false
        err.should contain("no-deps")
      end
    end
  end

  it "throws when a dependency requires something it does not own" do
    It.with_registry do |registry|
      registry.add("various-requires", "1.0.0", It.pkg("various-requires", "1.0.0"),
        {"index.js" => "module.exports = require('no-deps')",
         "invalid-require.js" => "module.exports = require('no-deps')"})

      ic = Commands::Install::Config.new.copy_with(strategy: Data::Package::InstallStrategy::Pnp)
      It.install_project(registry, %({"name":"app","version":"1.0.0","dependencies":{"various-requires":"1.0.0"}}), install_config: ic) do |project|
        ok, _stdout, err = pnp_source(project, "require('various-requires/invalid-require')")
        ok.should be_false
        err.should contain("no-deps")
      end
    end
  end
end

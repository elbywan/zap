require "./spec_helper"

# More ports: topological install-script order (yarn classic
# "install should run install scripts in the order of dependencies") and
# berry pnp.js resolution cases (deep imports, folder index files, .js
# extension resolution).
describe "more resolution ports", tags: "integration" do
  it "runs install scripts in dependency order" do
    It.with_registry do |registry|
      tmpdir = Path.new(Dir.tempdir, "zap-tp-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(tmpdir)
        marker = tmpdir / "order.txt"
        mark = %(node -e "require('fs').appendFileSync(process.argv[2], process.argv[1])")
        registry.add("child", "1.0.0", It.pkg("child", "1.0.0", scripts: {"postinstall" => %(#{mark} child #{marker})}), {"index.js" => "c"})
        registry.add("parent", "1.0.0", It.pkg("parent", "1.0.0", dependencies: {"child" => "1.0.0"}, scripts: {"postinstall" => %(#{mark} parent #{marker})}), {"index.js" => "p"})

        It.install_project(registry, %({"name":"app","version":"1.0.0","dependencies":{"parent":"1.0.0"}})) do |_project|
          # Dependencies run before their dependents
          File.read(marker).should eq("childparent")
        end
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end

  it "resolves deep imports and relative imports through the pnp runtime" do
    It.with_registry do |registry|
      registry.add("pnp-pkg", "1.0.0", It.pkg("pnp-pkg", "1.0.0"),
        {"index.js" => "module.exports = require('./lib/relative')",
         "lib/relative.js" => "module.exports = 'relative'",
         "lib/deep.js" => "module.exports = 'deep'"})

      ic = Commands::Install::Config.new.copy_with(strategy: Data::Package::InstallStrategy::Pnp)
      It.install_project(registry, %({"name":"app","version":"1.0.0","dependencies":{"pnp-pkg":"1.0.0"}}), install_config: ic) do |project|
        out_io = IO::Memory.new
        err_io = IO::Memory.new
        status = Process.run("node", ["-e", "process.stdout.write(JSON.stringify({index: require('pnp-pkg'), deep: require('pnp-pkg/lib/deep')}))"],
          chdir: project.to_s, output: out_io, error: err_io, env: {"NODE_OPTIONS" => "--require #{project}/.pnp.cjs"})
        status.success?.should be_true, "pnp runtime error: #{err_io.to_s}"
        JSON.parse(out_io.to_s).should eq(JSON.parse(%({"index":"relative","deep":"deep"})))
      end
    end
  end

  it "resolves folder index files and .js extensions through the pnp runtime" do
    It.with_registry do |registry|
      registry.add("pnp-pkg", "1.0.0", It.pkg("pnp-pkg", "1.0.0"),
        {"index.js" => "module.exports = require('./folder')",
         "folder/index.js" => "module.exports = 'from-index'",
         "extension.js" => "module.exports = 'from-extension'"})

      ic = Commands::Install::Config.new.copy_with(strategy: Data::Package::InstallStrategy::Pnp)
      It.install_project(registry, %({"name":"app","version":"1.0.0","dependencies":{"pnp-pkg":"1.0.0"}}), install_config: ic) do |project|
        out_io = IO::Memory.new
        err_io = IO::Memory.new
        status = Process.run("node", ["-e", "process.stdout.write(JSON.stringify({folder: require('pnp-pkg/folder'), ext: require('pnp-pkg/extension')}))"],
          chdir: project.to_s, output: out_io, error: err_io, env: {"NODE_OPTIONS" => "--require #{project}/.pnp.cjs"})
        status.success?.should be_true, "pnp runtime error: #{err_io.to_s}"
        JSON.parse(out_io.to_s).should eq(JSON.parse(%({"folder":"from-index","ext":"from-extension"})))
      end
    end
  end
end

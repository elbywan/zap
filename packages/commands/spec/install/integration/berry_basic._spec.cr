require "./spec_helper"

# Ports of yarn berry's pkg-tests-specs (packages/pkg-tests/pkg-tests-specs/sources):
# "it should install the dependencies of any dependency fetched from a local
# directory" (basic.js) and friends.
describe "berry basic ports", tags: "integration" do
  it "installs the dependencies of a file: directory dependency" do
    It.with_registry do |registry|
      registry.add("dep-of-file", "1.0.0", It.pkg("dep-of-file", "1.0.0"), {"index.js" => "module.exports = {name: 'dep-of-file'}"})

      tmpdir = Path.new(Dir.tempdir, "zap-it-#{Random::Secure.hex(4)}")
      local = tmpdir / "local-pkg"
      begin
        Dir.mkdir_p(local)
        File.write(local / "package.json", %({"name":"local-pkg","version":"1.0.0","dependencies":{"dep-of-file":"1.0.0"},"main":"index.js"}))
        File.write(local / "index.js", "module.exports = require('dep-of-file')")
        app = tmpdir / "app"
        Dir.mkdir_p(app)
        File.write(app / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"local-pkg":"file:../local-pkg"}}))
        File.write(app / ".npmrc", "registry=#{registry.base_url}/\n")
        config = Core::Config.new.copy_with(prefix: app.to_s, store_path: (tmpdir / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: false)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)

        # The dependency of the linked folder stays nested under the symlink,
        # where node can resolve it from the link's real path (npm parity)
        File.read(local / "node_modules/dep-of-file/index.js").should contain("dep-of-file")
        # And the whole chain resolves at runtime
        out_io = IO::Memory.new
        status = Process.run("node", ["-e", "process.stdout.write(JSON.stringify(require('local-pkg')))"], chdir: app.to_s, output: out_io)
        status.success?.should be_true
        out_io.to_s.should eq(%({"name":"dep-of-file"}))
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end

  it "links a file: directory dependency with the isolated strategy" do
    It.with_registry do |registry|
      registry.add("dep-of-file", "1.0.0", It.pkg("dep-of-file", "1.0.0"), {"index.js" => "module.exports = {name: 'dep-of-file'}"})

      tmpdir = Path.new(Dir.tempdir, "zap-it-#{Random::Secure.hex(4)}")
      local = tmpdir / "local-pkg"
      begin
        Dir.mkdir_p(local)
        File.write(local / "package.json", %({"name":"local-pkg","version":"1.0.0","dependencies":{"dep-of-file":"1.0.0"},"main":"index.js"}))
        File.write(local / "index.js", "module.exports = require('dep-of-file')")
        app = tmpdir / "app"
        Dir.mkdir_p(app)
        File.write(app / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"local-pkg":"file:../local-pkg"}}))
        File.write(app / ".npmrc", "registry=#{registry.base_url}/\n")
        config = Core::Config.new.copy_with(prefix: app.to_s, store_path: (tmpdir / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: false, strategy: Data::Package::InstallStrategy::Isolated)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)

        File.symlink?(app / "node_modules/local-pkg").should be_true
        # The linked folder's dependency is available in the virtual store
        Dir.exists?(app / "node_modules/.store").should be_true
        out_io = IO::Memory.new
        status = Process.run("node", ["-e", "process.stdout.write(JSON.stringify(require('local-pkg')))"], chdir: app.to_s, output: out_io)
        status.success?.should be_true
        out_io.to_s.should eq(%({"name":"dep-of-file"}))
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end
end

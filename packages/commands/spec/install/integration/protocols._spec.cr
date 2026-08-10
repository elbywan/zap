require "./spec_helper"


# Install protocols, mirroring yarn's pkg-tests (filesystem archives, tarball
# URLs, local directories).
describe "install protocols", tags: "integration" do
  it "installs from a tarball url" do
    It.with_registry do |registry|
      registry.add("tarball-dep", "1.0.0", It.pkg("tarball-dep", "1.0.0"), {"index.js" => "tar"})
      tarball_url = "#{registry.base_url}/tarball-dep/-/tarball-dep-1.0.0.tgz"

      It.install_project(registry, %({"name":"app","version":"1.0.0","dependencies":{"tarball-dep":"#{tarball_url}"}})) do |project|
        File.read(project / "node_modules/tarball-dep/index.js").should eq("tar")
      end
    end
  end

  it "installs the dependencies of a tarball url" do
    It.with_registry do |registry|
      registry.add("no-deps", "1.0.0", It.pkg("no-deps", "1.0.0"), {"index.js" => "nd"})
      registry.add("with-dep", "1.0.0", It.pkg("with-dep", "1.0.0", dependencies: {"no-deps" => "1.0.0"}), {"index.js" => "wd"})
      tarball_url = "#{registry.base_url}/with-dep/-/with-dep-1.0.0.tgz"

      It.install_project(registry, %({"name":"app","version":"1.0.0","dependencies":{"with-dep":"#{tarball_url}"}})) do |project|
        File.exists?(project / "node_modules/with-dep/index.js").should be_true
        File.exists?(project / "node_modules/no-deps/index.js").should be_true
      end
    end
  end

  it "installs from a file: tarball" do
    It.with_registry do |registry|
      registry.add("file-tar", "1.0.0", It.pkg("file-tar", "1.0.0"), {"index.js" => "ft"})
      tarball_url = "#{registry.base_url}/file-tar/-/file-tar-1.0.0.tgz"
      tarball = HTTP::Client.get(tarball_url).body

      tmpdir = Path.new(Dir.tempdir, "zap-it-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(tmpdir)
        File.write(tmpdir / "file-tar-1.0.0.tgz", tarball)
        File.write(tmpdir / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"file-tar":"file:file-tar-1.0.0.tgz"}}))
        File.write(tmpdir / ".npmrc", "registry=#{registry.base_url}/\n")
        config = Core::Config.new.copy_with(prefix: tmpdir.to_s, store_path: (tmpdir / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: false)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)

        File.read(tmpdir / "node_modules/file-tar/index.js").should eq("ft")
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end

  it "installs exact versions and tilde ranges" do
    It.with_registry do |registry|
      registry.add("ver", "1.2.3", It.pkg("ver", "1.2.3"), {"index.js" => "1.2.3"})
      registry.add("ver", "1.2.9", It.pkg("ver", "1.2.9"), {"index.js" => "1.2.9"})
      registry.add("ver", "1.3.0", It.pkg("ver", "1.3.0"), {"index.js" => "1.3.0"})

      It.install_project(registry, %({"name":"app","version":"1.0.0","dependencies":{"ver":"1.2.3"}})) do |project|
        File.read(project / "node_modules/ver/index.js").should eq("1.2.3")
      end
      It.install_project(registry, %({"name":"app","version":"1.0.0","dependencies":{"ver":"~1.2.0"}})) do |project|
        File.read(project / "node_modules/ver/index.js").should eq("1.2.9")
      end
    end
  end

  it "links a dependency from a local directory via file:" do
    It.with_registry do |registry|
      tmpdir = Path.new(Dir.tempdir, "zap-it-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(tmpdir / "dir-dep")
        File.write(tmpdir / "dir-dep/package.json", %({"name":"dir-dep","version":"1.0.0","main":"index.js"}))
        File.write(tmpdir / "dir-dep/index.js", "dir")
        File.write(tmpdir / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"dir-dep":"file:./dir-dep"}}))
        File.write(tmpdir / ".npmrc", "registry=#{registry.base_url}/\n")
        config = Core::Config.new.copy_with(prefix: tmpdir.to_s, store_path: (tmpdir / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: false)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)

        File.read(tmpdir / "node_modules/dir-dep/index.js").should eq("dir")
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end
end

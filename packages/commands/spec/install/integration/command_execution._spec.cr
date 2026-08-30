require "../../../dlx/dlx"
require "../../../dlx/config"
require "../../../exec/exec"
require "../../../exec/config"
require "./spec_helper"

# Command execution and remaining linkers: exec resolves installed bins
# through node_modules/.bin, the pnp strategy writes its runtime files,
# and overrides can point at git sources.
describe "command execution", tags: "integration" do
  it "exec runs a command resolved through node_modules/.bin" do
    It.with_registry do |registry|
      registry.add("with-bin", "1.0.0", It.pkg("with-bin", "1.0.0", bin: "cli.js"),
        {"index.js" => "main", "cli.js" => "#!/usr/bin/env node\nrequire('fs').writeFileSync('exec-ran.txt','ok')"})

      It.install_project(registry, %({"name":"app","version":"1.0.0","dependencies":{"with-bin":"1.0.0"}})) do |project|
        exec_config = Core::Config.new.copy_with(prefix: project.to_s, silent: true)
        Commands::Exec.run(exec_config, Commands::Exec::Config.new(command: "with-bin"))
        File.read(project / "exec-ran.txt").should eq("ok")
      end
    end
  end

  it "writes the pnp runtime files with the pnp strategy" do
    It.with_registry do |registry|
      registry.add("b", "1.0.0", It.pkg("b", "1.0.0"), {"index.js" => "b"})
      registry.add("a", "1.0.0", It.pkg("a", "1.0.0", dependencies: {"b" => "1.0.0"}), {"index.js" => "a"})

      ic = Commands::Install::Config.new.copy_with(strategy: Data::Package::InstallStrategy::Pnp)
      It.install_project(registry, %({"name":"app","version":"1.0.0","dependencies":{"a":"1.0.0"}}), install_config: ic) do |project|
        File.exists?(project / ".pnp.cjs").should be_true
        File.exists?(project / ".pnp.loader.mjs").should be_true
        # No packages are linked into node_modules; only the .pnp data dir
        # (and the installed-state file)
        Dir.children(project / "node_modules").sort.should eq([".pnp", ".zap-fingerprint", ".zap-state"])
      end
    end
  end

  it "applies an override pointing at a git source" do
    It.with_registry do |registry|
      repo = Path.new(Dir.tempdir, "zap-git-#{Random::Secure.hex(4)}")
      begin
        It.make_git_repo(repo, %({"name":"git-dep","version":"1.0.0","main":"index.js"}), {"index.js" => "from-git"})
        registry.add("git-dep", "1.0.0", It.pkg("git-dep", "1.0.0"), {"index.js" => "from-registry"})

        It.install_project(
          registry,
          %({"name":"app","version":"1.0.0","dependencies":{"git-dep":"1.0.0"},"overrides":{"git-dep":"git+file://#{repo}"}})
        ) do |project|
          File.read(project / "node_modules/git-dep/index.js").should eq("from-git")
        end
      ensure
        FileUtils.rm_rf(repo)
      end
    end
  end
  it "dlx downloads and runs a package bin" do
    It.with_registry do |registry|
      registry.add("dlx-pkg", "1.0.0", It.pkg("dlx-pkg", "1.0.0", bin: "cli.js"),
        {"index.js" => "main", "cli.js" => "#!/usr/bin/env node\nrequire('fs').writeFileSync('dlx-ran.txt','ok')"})

      tmpdir = Path.new(Dir.tempdir, "zap-dlx-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(tmpdir)
        File.write(tmpdir / "package.json", %({"name":"app","version":"1.0.0"}))
        File.write(tmpdir / ".npmrc", "registry=#{registry.base_url}/\n")

        old_argv = ARGV.dup
        begin
          ARGV.replace(["dlx-pkg"])
          dlx_config = Core::Config.new.copy_with(prefix: tmpdir.to_s, silent: true)
          Dir.cd(tmpdir) do
            Commands::Dlx.run(dlx_config, Commands::Dlx::Config.new.copy_with(packages: ["dlx-pkg"], quiet: true))
          end
        ensure
          ARGV.replace(old_argv)
        end
        # The bin ran with the project directory as cwd
        File.read(tmpdir / "dlx-ran.txt").should eq("ok")
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end

  it "dlx runs the install scripts of the downloaded package" do
    It.with_registry do |registry|
      registry.add("dlx-scripted", "1.0.0", It.pkg("dlx-scripted", "1.0.0", bin: "cli.js",
        scripts: {"postinstall" => "node -e \"require('fs').writeFileSync('built.txt','yes')\""}),
        {"index.js" => "main", "cli.js" => "#!/usr/bin/env node\nrequire('fs').writeFileSync('dlx-scripted-ran.txt','ok')"})

      tmpdir = Path.new(Dir.tempdir, "zap-dlx-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(tmpdir)
        File.write(tmpdir / "package.json", %({"name":"app","version":"1.0.0"}))
        File.write(tmpdir / ".npmrc", "registry=#{registry.base_url}/\n")

        old_argv = ARGV.dup
        begin
          ARGV.replace(["dlx-scripted"])
          dlx_config = Core::Config.new.copy_with(prefix: tmpdir.to_s, silent: true)
          Dir.cd(tmpdir) do
            Commands::Dlx.run(dlx_config, Commands::Dlx::Config.new.copy_with(packages: ["dlx-scripted"], quiet: true))
          end
        ensure
          ARGV.replace(old_argv)
        end
        File.read(tmpdir / "dlx-scripted-ran.txt").should eq("ok")
        # The postinstall ran during the dlx install (the strict default
        # would otherwise block it)
        dlx_dir = Path.new(Dir.tempdir) / "zap--dlx-#{Digest::SHA1.hexdigest("dlx-scripted@*")}"
        File.read(dlx_dir / "node_modules/dlx-scripted/built.txt").should eq("yes")
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end

  it "dlx is not quarantined by the release age gate" do
    It.with_registry do |registry|
      registry.add("dlx-fresh", "1.0.0", It.pkg("dlx-fresh", "1.0.0", bin: "cli.js"),
        {"index.js" => "main", "cli.js" => "#!/usr/bin/env node\nrequire('fs').writeFileSync('dlx-fresh-ran.txt','ok')"},
        published_at: Time.utc - 1.hour)

      tmpdir = Path.new(Dir.tempdir, "zap-dlx-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(tmpdir)
        File.write(tmpdir / "package.json", %({"name":"app","version":"1.0.0"}))
        File.write(tmpdir / ".npmrc", "registry=#{registry.base_url}/\n")

        old_argv = ARGV.dup
        begin
          ARGV.replace(["dlx-fresh"])
          dlx_config = Core::Config.new.copy_with(prefix: tmpdir.to_s, silent: true)
          Dir.cd(tmpdir) do
            Commands::Dlx.run(dlx_config, Commands::Dlx::Config.new.copy_with(packages: ["dlx-fresh"], quiet: true))
          end
        ensure
          ARGV.replace(old_argv)
        end
        File.read(tmpdir / "dlx-fresh-ran.txt").should eq("ok")
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end
end

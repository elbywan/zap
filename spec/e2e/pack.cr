require "./harness"

# The `zap pack` command against the real binary: a local package becomes
# a deterministic, self-contained tarball that both zap and npm install.
describe "zap pack", tags: "e2e" do
  it "packs a package installable by zap and npm, deterministically" do
    work = File.join(E2E.work, "packed")
    Dir.mkdir_p(File.join(work, "lib"))
    File.write(File.join(work, "package.json"), %({"name":"e2e-packed","version":"1.2.3","main":"index.js","bin":{"e2e-packed":"cli.js"},"files":["lib"]}))
    File.write(File.join(work, "index.js"), "module.exports = 42\n")
    File.write(File.join(work, "cli.js"), "#!/usr/bin/env node\nconsole.log(42)\n")
    File.write(File.join(work, "lib", "util.js"), "util\n")
    File.write(File.join(work, "lib", "ignored.js"), "ignored\n")
    File.write(File.join(work, ".gitignore"), "ignored.js\n")

    ok, output = E2E.zap(work, "pack")
    ok.should be_true, "pack failed: #{output}"
    archive = File.join(work, "package.tgz")
    File.exists?(archive).should be_true
    first_bytes = File.read(archive)

    # Repeated packs are byte-identical.
    ok, output = E2E.zap(work, "pack")
    ok.should be_true, "second pack failed: #{output}"
    File.read(archive).should eq(first_bytes)

    # zap installs the tarball through a file: dependency; the whitelist
    # and the .gitignore exclusion are honored.
    project = E2E.make_project(%({"e2e-packed":"file:../packed/package.tgz"}), E2E.auth_npmrc)
    ok, output = E2E.zap(project, "install", "--frozen-lockfile=false")
    ok.should be_true, "zap install of the packed tarball failed: #{output}"
    E2E.assert_installed(project, ["e2e-packed"])
    File.read(File.join(project, "node_modules", "e2e-packed", "index.js")).should eq("module.exports = 42\n")
    File.exists?(File.join(project, "node_modules", "e2e-packed", "lib", "ignored.js")).should be_false

    # npm installs the same tarball.
    npm_project = File.join(E2E.work, "npm-app-#{Random.rand(100000)}")
    Dir.mkdir_p(npm_project)
    File.write(File.join(npm_project, "package.json"), %({"name":"npm-app","version":"1.0.0","dependencies":{"e2e-packed":"file:../packed/package.tgz"}}))
    npm_output = IO::Memory.new
    status = Process.run("node", [E2E.npm_cli, "install", "--no-audit", "--no-fund"], chdir: npm_project, output: npm_output, error: npm_output)
    status.success?.should be_true, "npm install of the packed tarball failed: #{npm_output.to_s}"
    File.exists?(File.join(npm_project, "node_modules", "e2e-packed", "index.js")).should be_true
  end
end

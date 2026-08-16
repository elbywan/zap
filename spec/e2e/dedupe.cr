require "./harness"

# The one-shot `zap dedupe` command against the real registry: a tree
# genuinely holding two versions of the same package collapses to the
# highest version in use, the physical tree relocates, and the lockfile
# stops churning.
describe "zap dedupe against a real registry", tags: "e2e" do
  it "collapses a diverged transitive to the highest in-use version" do
    # The root dependency is declared as a range: the dedupe must keep the
    # declared specifier in the lockfile root and only move the pins.
    project = E2E.make_project(%({"chalk":"2.4.2","debug":"4.3.4","supports-color":"^5.3.0"}), E2E.auth_npmrc)
    ok, output = E2E.zap(project, "install", "--frozen-lockfile=false")
    ok.should be_true, "install failed: #{output}"
    E2E.assert_installed(project, ["chalk", "debug", "supports-color"])

    # Rewire the tree into a genuine divergence: chalk's transitive pin
    # drops to 5.3.0 while the direct dependency stays at 5.5.0 (the
    # highest in use), as a stale lockfile written before 5.5.0 existed
    # would have left it.
    lock_path = File.join(project, "zap.lock")
    lock = File.read(lock_path)
    # Rewire chalk's transitive pin inside its own entry (the root's
    # pinned_dependencies also lists 5.5.0 and must stay untouched).
    chalk_match = lock.match(/\n  chalk@2\.4\.2:\n((?:    .*\n)*)/)
    chalk_match.should_not be_nil, "chalk entry not found in lockfile"
    chalk_block = chalk_match.not_nil![1]
    chalk_block.should contain("supports-color: 5.5.0"), "chalk entry missing the 5.5.0 pin: #{chalk_block}"
    rewired = chalk_block.sub("supports-color: 5.5.0", "supports-color: 5.3.0")
    lock = lock.sub(chalk_block, rewired)
    entry_530 = <<-YAML
      supports-color@5.3.0:
        name: supports-color
        version: 5.3.0
        dependencies:
          has-flag: 3.0.0
        engines:
          node: '>=4'
        roots:
        - e2e
        dist:
          tarball: #{E2E.base_url}/supports-color/-/supports-color-5.3.0.tgz
          shasum: 5b24ac15db80fa927cf5227a4a33fd3c4c7676c0
          integrity: sha512-0aP01LLIskjKs3lq52EC0aGBAJhLq7B2Rd8HC/DR/PtNNpcLilNmHC12O+hu0usQpo7wtHNRqtrhBwtDb0+dNg==
    YAML
    lock = lock.sub("  supports-color@5.5.0:", entry_530 + "\n" + "  supports-color@5.5.0:")
    File.write(lock_path, lock)

    # Materialize the diverged tree: root node_modules holds 5.5.0 (the
    # direct pin) and chalk gets its own nested 5.3.0 copy.
    ok, output = E2E.zap(project, "install", "--frozen-lockfile=false")
    ok.should be_true, "diverged install failed: #{output}"
    root_version = File.read(File.join(project, "node_modules", "supports-color", "package.json"))
    JSON.parse(root_version)["version"].as_s.should eq("5.5.0")
    nested = File.join(project, "node_modules", "chalk", "node_modules", "supports-color", "package.json")
    File.exists?(nested).should be_true, "expected a nested supports-color@5.3.0 copy"
    JSON.parse(File.read(nested))["version"].as_s.should eq("5.3.0")

    # The one-shot dedupe collapses both onto 5.5.0.
    ok, output = E2E.zap(project, "dedupe", "--frozen-lockfile=false")
    ok.should be_true, "dedupe failed: #{output}"
    lock = File.read(lock_path)
    lock.should_not contain("supports-color@5.3.0")
    lock.should contain("supports-color@5.5.0")
    # The declared range survives in the root entry; the pins are exact.
    lock.should contain("      supports-color: ^5.3.0\n    pinned_dependencies:")
    lock.should contain("      supports-color: 5.5.0\n      escape-string-regexp: 1.0.5")
    File.exists?(nested).should be_false, "nested 5.3.0 copy should be gone"
    JSON.parse(File.read(File.join(project, "node_modules", "supports-color", "package.json")))["version"].as_s.should eq("5.5.0")

    # A subsequent install is a no-op and leaves the lockfile byte-identical.
    lock_after_dedupe = File.read(lock_path)
    ok, output = E2E.zap(project, "install", "--frozen-lockfile=false")
    ok.should be_true, "reinstall failed: #{output}"
    output.should contain("up to date")
    File.read(lock_path).should eq(lock_after_dedupe)
  end
end

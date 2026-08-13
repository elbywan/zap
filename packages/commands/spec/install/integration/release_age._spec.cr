require "./spec_helper"

# The recently-published quarantine: newly resolved versions younger than
# zap.minimum_release_age are refused, while lockfile-pinned versions, the
# --allow-recent flag, exempted names and a zero threshold pass. Registries
# without a time field (like the fixture registry by default) cannot enforce
# the gate and fail open.
describe "release age", tags: "integration" do
  it "refuses a newly resolved version younger than the minimum release age" do
    It.with_registry do |registry|
      registry.add("fresh", "1.0.0", It.pkg("fresh", "1.0.0"), {"index.js" => "f"},
        published_at: Time.utc - 1.hour)

      raised = false
      begin
        It.install_project(registry, %({"name":"app","version":"1.0.0","dependencies":{"fresh":"1.0.0"}})) { |_| }
      rescue ex
        raised = true
        ex.message.not_nil!.should contain("minimum release age")
        ex.message.not_nil!.should contain("fresh@1.0.0")
      end
      raised.should be_true
    end
  end

  it "allows a version older than the minimum release age" do
    It.with_registry do |registry|
      registry.add("aged", "1.0.0", It.pkg("aged", "1.0.0"), {"index.js" => "a"},
        published_at: Time.utc - 10.days)

      It.install_project(registry, %({"name":"app","version":"1.0.0","dependencies":{"aged":"1.0.0"}})) do |project|
        File.read(project / "node_modules/aged/index.js").should eq("a")
      end
    end
  end

  it "allows young versions when the threshold is zero" do
    It.with_registry do |registry|
      registry.add("fresh", "1.0.0", It.pkg("fresh", "1.0.0"), {"index.js" => "f"},
        published_at: Time.utc - 1.hour)

      It.install_project(registry, %({"name":"app","version":"1.0.0","dependencies":{"fresh":"1.0.0"},"zap":{"minimum_release_age":"0"}})) do |project|
        File.read(project / "node_modules/fresh/index.js").should eq("f")
      end
    end
  end

  it "allows young versions with the --allow-recent flag" do
    It.with_registry do |registry|
      registry.add("fresh", "1.0.0", It.pkg("fresh", "1.0.0"), {"index.js" => "f"},
        published_at: Time.utc - 1.hour)

      ic = Commands::Install::Config.new.copy_with(allow_recent: true)
      It.install_project(registry, %({"name":"app","version":"1.0.0","dependencies":{"fresh":"1.0.0"}}), install_config: ic) do |project|
        File.read(project / "node_modules/fresh/index.js").should eq("f")
      end
    end
  end

  it "allows exempted package names" do
    It.with_registry do |registry|
      registry.add("fresh", "1.0.0", It.pkg("fresh", "1.0.0"), {"index.js" => "f"},
        published_at: Time.utc - 1.hour)

      It.install_project(registry, %({"name":"app","version":"1.0.0","dependencies":{"fresh":"1.0.0"},"zap":{"minimum_release_age_exemptions":["fresh"]}})) do |project|
        File.read(project / "node_modules/fresh/index.js").should eq("f")
      end
    end
  end

  it "accepts hour and minute units" do
    It.with_registry do |registry|
      registry.add("fresh", "1.0.0", It.pkg("fresh", "1.0.0"), {"index.js" => "f"},
        published_at: Time.utc - 30.minutes)

      raised = false
      begin
        It.install_project(registry, %({"name":"app","version":"1.0.0","dependencies":{"fresh":"1.0.0"},"zap":{"minimum_release_age":"24h"}})) { |_| }
      rescue ex
        raised = true
        ex.message.not_nil!.should contain("minimum release age")
      end
      raised.should be_true
    end
  end

  it "rejects an invalid minimum_release_age value" do
    It.with_registry do |registry|
      registry.add("fresh", "1.0.0", It.pkg("fresh", "1.0.0"), {"index.js" => "f"},
        published_at: Time.utc - 10.days)

      raised = false
      begin
        It.install_project(registry, %({"name":"app","version":"1.0.0","dependencies":{"fresh":"1.0.0"},"zap":{"minimum_release_age":"soon"}})) { |_| }
      rescue ex
        raised = true
        ex.message.not_nil!.should contain("Invalid zap.minimum_release_age")
      end
      raised.should be_true
    end
  end

  it "accepts minute units" do
    It.with_registry do |registry|
      registry.add("fresh", "1.0.0", It.pkg("fresh", "1.0.0"), {"index.js" => "f"},
        published_at: Time.utc - 30.minutes)

      raised = false
      begin
        It.install_project(registry, %({"name":"app","version":"1.0.0","dependencies":{"fresh":"1.0.0"},"zap":{"minimum_release_age":"90m"}})) { |_| }
      rescue ex
        raised = true
        ex.message.not_nil!.should contain("minimum release age")
      end
      raised.should be_true
    end
  end

  it "allows a lockfile-pinned version on a later install" do
    It.with_registry do |registry|
      registry.add("fresh", "1.0.0", It.pkg("fresh", "1.0.0"), {"index.js" => "f"},
        published_at: Time.utc - 1.hour)

      tmpdir = Path.new(Dir.tempdir, "zap-it-#{Random::Secure.hex(4)}")
      begin
        Dir.mkdir_p(tmpdir)
        File.write(tmpdir / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"fresh":"1.0.0"},"zap":{"minimum_release_age":"0"}}))
        File.write(tmpdir / ".npmrc", "registry=#{registry.base_url}/\n")
        config = Core::Config.new.copy_with(prefix: tmpdir.to_s, store_path: (tmpdir / "store").to_s, silent: true)
        ic = Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true)
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)

        # The version is now pinned in the lockfile: the default threshold
        # no longer applies.
        File.write(tmpdir / "package.json", %({"name":"app","version":"1.0.0","dependencies":{"fresh":"1.0.0"}}))
        Commands::Install.run(config, ic, raise_on_failure: true, reporter: Reporter::Null.new)
        File.read(tmpdir / "node_modules/fresh/index.js").should eq("f")
      ensure
        FileUtils.rm_rf(tmpdir)
      end
    end
  end
end

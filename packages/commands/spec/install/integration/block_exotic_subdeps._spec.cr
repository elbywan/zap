require "./spec_helper"

# pnpm's blockExoticSubdeps: transitive dependencies must come from the
# registry; git, tarball, file and workspace sources are only allowed for
# direct dependencies the user explicitly requested.
describe "block exotic subdeps", tags: "integration" do
  it "refuses a transitive git dependency when enabled" do
    It.with_registry do |registry|
      repo = Path.new(Dir.tempdir, "zap-git-#{Random::Secure.hex(4)}")
      begin
        It.make_git_repo(repo, %({"name":"git-dep","version":"1.0.0"}), {"index.js" => "g"})
        registry.add("parent", "1.0.0", It.pkg("parent", "1.0.0",
          dependencies: {"git-dep" => "git+file://#{repo}"}),
          {"index.js" => "p"})

        raised = false
        begin
          It.install_project(registry, %({"name":"app","version":"1.0.0","dependencies":{"parent":"1.0.0"},"zap":{"block_exotic_subdeps":true}})) { |_| }
        rescue ex
          raised = true
          ex.message.not_nil!.should contain("block_exotic_subdeps")
          ex.message.not_nil!.should contain("git-dep")
        end
        raised.should be_true
      ensure
        FileUtils.rm_rf(repo)
      end
    end
  end

  it "allows direct git dependencies when enabled" do
    It.with_registry do |registry|
      repo = Path.new(Dir.tempdir, "zap-git-#{Random::Secure.hex(4)}")
      begin
        It.make_git_repo(repo, %({"name":"git-dep","version":"1.0.0"}), {"index.js" => "g"})

        It.install_project(registry, %({"name":"app","version":"1.0.0","dependencies":{"git-dep":"git+file://#{repo}"},"zap":{"block_exotic_subdeps":true}})) do |project|
          File.read(project / "node_modules/git-dep/index.js").should eq("g")
        end
      ensure
        FileUtils.rm_rf(repo)
      end
    end
  end

  it "allows transitive registry dependencies when enabled" do
    It.with_registry do |registry|
      registry.add("child", "1.0.0", It.pkg("child", "1.0.0"), {"index.js" => "c"})
      registry.add("parent", "1.0.0", It.pkg("parent", "1.0.0", dependencies: {"child" => "1.0.0"}), {"index.js" => "p"})

      It.install_project(registry, %({"name":"app","version":"1.0.0","dependencies":{"parent":"1.0.0"},"zap":{"block_exotic_subdeps":true}})) do |project|
        File.read(project / "node_modules/parent/index.js").should eq("p")
        File.read(project / "node_modules/child/index.js").should eq("c")
      end
    end
  end
end

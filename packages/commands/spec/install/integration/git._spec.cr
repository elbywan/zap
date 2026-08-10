require "./spec_helper"


# Git protocol installs against local repositories (git+file://), exercising
# the clone -> prepare -> pack -> store pipeline.
describe "git dependencies", tags: "integration" do
  it "installs a package from a git repository" do
    It.with_registry do |registry|
      registry.add("git-reg-dep", "1.0.0", It.pkg("git-reg-dep", "1.0.0"), {"index.js" => "reg"})
      repo = Path.new(Dir.tempdir, "zap-git-#{Random::Secure.hex(4)}")
      begin
        It.make_git_repo(
          repo,
          %({"name":"git-pkg","version":"1.0.0","main":"index.js","dependencies":{"git-reg-dep":"1.0.0"}}),
          {"index.js" => "from-git"}
        )

        It.install_project(registry, %({"name":"app","version":"1.0.0","dependencies":{"git-pkg":"git+file://#{repo}"}})) do |project|
          File.read(project / "node_modules/git-pkg/index.js").should eq("from-git")
          # The git package's registry dependency is installed from the consumer's registry
          File.read(project / "node_modules/git-reg-dep/index.js").should eq("reg")
        end
      ensure
        FileUtils.rm_rf(repo)
      end
    end
  end

  it "runs the prepare script for git dependencies" do
    It.with_registry do |registry|
      repo = Path.new(Dir.tempdir, "zap-git-#{Random::Secure.hex(4)}")
      begin
        It.make_git_repo(
          repo,
          It.json(It.pkg("git-prepared", "1.0.0", scripts: {"prepare" => %(node -e "require('fs').writeFileSync('prepared.txt','yes')")})).to_json,
          {"index.js" => "prepared"}
        )

        It.install_project(registry, %({"name":"app","version":"1.0.0","dependencies":{"git-prepared":"git+file://#{repo}"}})) do |project|
          File.read(project / "node_modules/git-prepared/index.js").should eq("prepared")
          # The prepare script ran during the build and its output is packed
          File.read(project / "node_modules/git-prepared/prepared.txt").should eq("yes")
        end
      ensure
        FileUtils.rm_rf(repo)
      end
    end
  end
end

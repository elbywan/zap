require "./spec_helper"


# Git protocol edge cases: commit-ish refs, branch refs and semver tag ranges.
describe "git dependencies edge cases", tags: "integration" do
  it "installs a specific commit" do
    It.with_registry do |registry|
      repo = Path.new(Dir.tempdir, "zap-git-#{Random::Secure.hex(4)}")
      begin
        It.make_git_repo(repo, %({"name":"git-sha","version":"1.0.0","main":"index.js"}), {"index.js" => "v1"})
        sha = `git -C #{repo} rev-parse HEAD`.strip

        It.install_project(registry, %({"name":"app","version":"1.0.0","dependencies":{"git-sha":"git+file://#{repo}##{sha}"}})) do |project|
          File.read(project / "node_modules/git-sha/index.js").should eq("v1")
        end
      ensure
        FileUtils.rm_rf(repo)
      end
    end
  end

  it "installs a branch ref" do
    It.with_registry do |registry|
      repo = Path.new(Dir.tempdir, "zap-git-#{Random::Secure.hex(4)}")
      begin
        It.make_git_repo(repo, %({"name":"git-branch","version":"1.0.0","main":"index.js"}), {"index.js" => "main"})

        It.install_project(registry, %({"name":"app","version":"1.0.0","dependencies":{"git-branch":"git+file://#{repo}#main"}})) do |project|
          File.read(project / "node_modules/git-branch/index.js").should eq("main")
        end
      ensure
        FileUtils.rm_rf(repo)
      end
    end
  end

  it "resolves a semver tag range" do
    It.with_registry do |registry|
      repo = Path.new(Dir.tempdir, "zap-git-#{Random::Secure.hex(4)}")
      begin
        It.make_git_repo(repo, %({"name":"git-semver","version":"1.0.0","main":"index.js"}), {"index.js" => "v1"})
        Process.run("git", ["-C", repo.to_s, "tag", "1.0.0"])
        # Add a 2.x tag
        File.write(repo / "index.js", "v2")
        Process.run("git", ["-C", repo.to_s, "add", "."])
        env = {"GIT_AUTHOR_NAME" => "zap-tests", "GIT_AUTHOR_EMAIL" => "zap-tests@example.com", "GIT_COMMITTER_NAME" => "zap-tests", "GIT_COMMITTER_EMAIL" => "zap-tests@example.com"}
        Process.run("git", ["-C", repo.to_s, "commit", "-q", "-m", "v2"], env: env)
        Process.run("git", ["-C", repo.to_s, "tag", "2.0.0"])

        It.install_project(registry, %({"name":"app","version":"1.0.0","dependencies":{"git-semver":"git+file://#{repo}#semver:^1.0.0"}})) do |project|
          File.read(project / "node_modules/git-semver/index.js").should eq("v1")
        end

        It.install_project(registry, %({"name":"app","version":"1.0.0","dependencies":{"git-semver":"git+file://#{repo}#semver:^2.0.0"}})) do |project|
          File.read(project / "node_modules/git-semver/index.js").should eq("v2")
        end
      ensure
        FileUtils.rm_rf(repo)
      end
    end
  end
end

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

  it "installs a git package whose nested dependencies race the parent link" do
    It.with_registry do |registry|
      # b@1 is nested under a, and its c@1 child is nested under b@1: the
      # child's mkdir creates node_modules/a/node_modules/b/node_modules while
      # the a and b clonefile links are still in flight.
      registry.add("a", "1.0.0", It.pkg("a", "1.0.0", dependencies: {"b" => "1.0.0"}), {"index.js" => "a"})
      registry.add("b", "1.0.0", It.pkg("b", "1.0.0", dependencies: {"c" => "1.0.0"}), {"index.js" => "b1"})
      registry.add("b", "2.0.0", It.pkg("b", "2.0.0", dependencies: {"c" => "2.0.0"}), {"index.js" => "b2"})
      registry.add("c", "1.0.0", It.pkg("c", "1.0.0"), {"index.js" => "c1"})
      registry.add("c", "2.0.0", It.pkg("c", "2.0.0"), {"index.js" => "c2"})

      repo = Path.new(Dir.tempdir, "zap-git-#{Random::Secure.hex(4)}")
      begin
        It.make_git_repo(
          repo,
          It.pkg("git-nested", "1.0.0",
            dependencies: {"a" => "1.0.0", "b" => "2.0.0"},
            scripts: {"prepare" => "true"}).to_json,
          {"index.js" => "from-git"}
        )

        It.install_project(registry, %({"name":"app","version":"1.0.0","dependencies":{"git-nested":"git+file://#{repo}"}})) do |project|
          File.read(project / "node_modules/git-nested/index.js").should eq("from-git")
          File.read(project / "node_modules/a/index.js").should eq("a")
          File.read(project / "node_modules/b/index.js").should eq("b2")
          File.read(project / "node_modules/a/node_modules/b/index.js").should eq("b1")
        end
      ensure
        FileUtils.rm_rf(repo)
      end
    end
  end

  it "reinstalls a transitive git dependency from the lockfile pin" do
    It.with_registry do |registry|
      repo = Path.new(Dir.tempdir, "zap-git-#{Random::Secure.hex(4)}")
      begin
        It.make_git_repo(repo, %({"name":"git-pkg","version":"1.0.0","main":"index.js"}), {"index.js" => "from-git"})
        registry.add("parent", "1.0.0", It.pkg("parent", "1.0.0", dependencies: {"git-pkg" => "git+file://#{repo}"}), {"index.js" => "p"})

        It.install_project(registry, %({"name":"app","version":"1.0.0","dependencies":{"parent":"1.0.0"}})) do |project|
          # The parent's lockfile deps pin the git dependency by its resolved
          # commit hash; a second install must route the bare-hash specifier
          # back to the git resolver instead of the registry fallback.
          Commands::Install.run(
            Core::Config.new.copy_with(prefix: project.to_s, store_path: (project / "store").to_s, silent: true),
            Commands::Install::Config.new.copy_with(workers: 1, frozen_lockfile: false, save: true),
            raise_on_failure: true, reporter: Reporter::Null.new
          )
          File.read(project / "node_modules/parent/node_modules/git-pkg/index.js").should eq("from-git")
        end
      ensure
        FileUtils.rm_rf(repo)
      end
    end
  end
end

require "./spec_helper"

# Failure semantics: missing direct/transitive dependencies abort the
# install, while optional ones are skipped (matches npm/yarn/pnpm).
describe "failure semantics", tags: "integration" do
  it "raises when a direct dependency is missing from the registry" do
    It.with_registry do |registry|
      expect_raises(Exception, /ghost-pkg/) do
        It.install_project(registry, %({"name":"app","version":"1.0.0","dependencies":{"ghost-pkg":"1.0.0"}})) { }
      end
    end
  end

  it "raises when a transitive dependency is missing from the registry" do
    It.with_registry do |registry|
      registry.add("present", "1.0.0", It.pkg("present", "1.0.0", dependencies: {"ghost-pkg" => "1.0.0"}), {"index.js" => "present"})

      expect_raises(Exception, /ghost-pkg/) do
        It.install_project(registry, %({"name":"app","version":"1.0.0","dependencies":{"present":"1.0.0"}})) { }
      end
    end
  end

  it "raises when no version satisfies the requested range" do
    It.with_registry do |registry|
      registry.add("ranged", "1.0.0", It.pkg("ranged", "1.0.0"), {"index.js" => "1.0.0"})

      expect_raises(Exception, /ranged/) do
        It.install_project(registry, %({"name":"app","version":"1.0.0","dependencies":{"ranged":"^99.0.0"}})) { }
      end
    end
  end
end

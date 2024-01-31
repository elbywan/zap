require "spec"
require "./fixtures/*"
require "./semver"

include Zap::Utils

describe Zap::Utils::Semver, tags: {"utils", "utils.semver"} do
  describe "equality" do
    EQUALITY_FIXTURES.each { |fixture|
      it "should parse { \"version\": \"#{fixture[0]}\" }" do
        Semver.parse(fixture[0]).canonical.should eq(fixture[1])
      end

      fixture[2].each { |v|
        it "should validate #{v} against { \"version\": \"#{fixture[0]}\" }" do
          semver = Semver.parse(fixture[0])
          semver.satisfies?(v).should be_true
        end
      }
      fixture[3].each { |v|
        it "should reject #{v} against { \"version\": \"#{fixture[0]}\" }" do
          semver = Semver.parse(fixture[0])
          semver.satisfies?(v).should be_false
        end
      }
    }
  end

  describe "range inclusion" do
    RANGE_INCLUSION_FIXTURES.each { |fixture|
      shift_fixture = fixture.size == 2

      it "should parse { \"version\": \"#{fixture[0]}\" }" do
        Semver.parse(fixture[0]).canonical.should eq(fixture[shift_fixture ? 0 : 1])
      end

      it "should validate #{fixture[shift_fixture ? 1 : 2]} against { \"version\": \"#{fixture[0]}\" }" do
        semver = Semver.parse(fixture[0])
        semver.satisfies?(fixture[shift_fixture ? 1 : 2]).should be_true
      end
    }
  end

  describe "range exclusion" do
    RANGE_EXCLUSION_FIXTURES.each { |fixture|
      shift_fixture = fixture.size == 2

      it "should reject #{fixture[shift_fixture ? 1 : 2]} against { \"version\": \"#{fixture[0]}\" }" do
        semver = Semver.parse(fixture[0])
        semver.satisfies?(fixture[shift_fixture ? 1 : 2]).should be_false
      end
    }
  end

  describe "comparator set intersection" do
    COMPARATOR_INTERSECTION_FIXTURES.each { |fixture|
      it "should intersect #{fixture[0]} and #{fixture[1]}" do
        range1 = Semver.parse(fixture[0])
        range2 = Semver.parse(fixture[1])
        range1.comparator_sets.size.should eq 1
        range2.comparator_sets.size.should eq 1
        comparator_set_1 = range1.comparator_sets[0]
        comparator_set_2 = range2.comparator_sets[0]
        comparator_set_1.intersection?(comparator_set_2).to_s.should eq(fixture[2])
      end
    }
  end

  describe "range intersection" do
    RANGE_INTERSECTION_FIXTURES.each { |fixture|
      it "should intersect #{fixture[0]} and #{fixture[1]}" do
        range1 = Semver.parse(fixture[0])
        range2 = Semver.parse(fixture[1])
        range1.intersection?(range2).to_s.should eq(fixture[2])
      end
    }
  end
end

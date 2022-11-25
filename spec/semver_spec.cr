require "./spec_helper"
require "./fixtures/semver/*"
require "../src/utils/semver"

include Zap::Utils

describe Zap::Utils::Semver do
  describe "equality" do
    EQUALITY_FIXTURES.each { |fixture|
      it "should parse { \"version\": \"#{fixture[0]}\" }" do
        Semver.parse(fixture[0]).canonical.should eq(fixture[1])
      end

      fixture[2].each { |v|
        it "should validate #{v} against { \"version\": \"#{fixture[0]}\" }" do
          semver = Semver.parse(fixture[0])
          semver.valid?(v).should be_true
        end
      }
      fixture[3].each { |v|
        it "should reject #{v} against { \"version\": \"#{fixture[0]}\" }" do
          semver = Semver.parse(fixture[0])
          semver.valid?(v).should be_false
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
        semver.valid?(fixture[shift_fixture ? 1 : 2]).should be_true
      end
    }
  end

  describe "range exclusion" do
    RANGE_EXCLUSION_FIXTURES.each { |fixture|
      shift_fixture = fixture.size == 2

      # it "should parse { \"version\": \"#{fixture[0]}\" }" do
      #   Semver.canonical(Semver.parse(fixture[0])).should eq(fixture[shift_fixture ? 0 : 1])
      # end

      it "should reject #{fixture[shift_fixture ? 1 : 2]} against { \"version\": \"#{fixture[0]}\" }" do
        semver = Semver.parse(fixture[0])
        semver.valid?(fixture[shift_fixture ? 1 : 2]).should be_false
      end
    }
  end
end

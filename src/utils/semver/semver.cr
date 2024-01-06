require "./range"

module Zap::Utils::Semver
  def self.parse(str : String) : Range
    Range.parse(str)
  end

  def self.parse?(str : String) : Range?
    Range.parse?(str)
  end
end

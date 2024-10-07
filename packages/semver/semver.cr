require "./range"

module Semver
  def self.parse(str : String) : Range
    Range.parse(str)
  end

  def self.parse?(str : String) : Range?
    Range.parse?(str)
  end
end

require "./range"

# **This module provides functionality for handling Semantic Versioning (Semver).**
#
# Semantic Versioning is a versioning scheme that uses a three-part version number:
# <major version>.<minor version>.<patch version>
#
# @see https://semver.org
#
# It also includes various features and handles additional features from the
# `node-semver` npm package.
# @see https://github.com/npm/node-semver
#
# ## Example
#
# ```
# require "semver"
# range = Semver.parse(">= 1.0.0 < 2.0.0")
# range.satisfies?("1.0.0") # => true
# range.satisfies?("0.9.9") # => false
# range.satisfies?("2.0.0") # => false
# ```
module Semver
  # Parses a semantic versioning string into a `Range` object.
  def self.parse(str : String) : Range
    Range.parse(str)
  end

  # Attempts to parse a semantic versioning string into a `Range` object.
  def self.parse?(str : String) : Range?
    Range.parse?(str)
  end
end

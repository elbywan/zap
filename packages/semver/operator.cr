# This module defines the Semver (Semantic Versioning) operators.
module Semver
  # Enum representing different comparison operators for semantic versioning.
  enum Operator
    # Represents the 'greater than' (>) operator.
    GreaterThan
    # Represents the 'greater than or equal to' (>=) operator.
    GreaterThanOrEqual
    # Represents the 'less than' (<) operator.
    LessThan
    # Represents the 'less than or equal to' (<=) operator.
    LessThanOrEqual
    # Represents the 'exact match' (=) operator.
    ExactMatch
  end
end

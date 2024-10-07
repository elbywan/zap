module Semver
  enum Operator
    # >
    GreaterThan
    # >=
    GreaterThanOrEqual
    # <
    LessThan
    # <=
    LessThanOrEqual
    # =
    ExactMatch
  end
end

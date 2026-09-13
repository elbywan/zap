# Optional per-phase timing hook for the fetch orchestration.
#
# When a hook is installed (the install command's --timings flag does),
# fetch_with_cache reports the duration of each phase it runs — the
# network fetch, the cache lookup, the body transform, the cache write —
# as (name, nanoseconds). Unset by default, so every phase costs one nil
# check.
module Fetch::Timings
  class_property hook : Proc(Symbol, Int64, Nil)? = nil

  def self.measure(name : Symbol, &)
    callback = @@hook
    return yield unless callback
    t0 = Time.monotonic
    begin
      yield
    ensure
      callback.call(name, (Time.monotonic - t0).total_nanoseconds.to_i64)
    end
  end
end

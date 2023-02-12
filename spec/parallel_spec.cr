require "./spec_helper"
require "../src/utils/parallel"

describe Zap::Utils::Parallel do
  it("should parallelize computations (index)") do
    10.times do
      results = Zap::Utils::Parallel.parallelize(10) { |i|
        # Shuffle the fibers
        sleep(Random.rand(10).milliseconds)
        # Perform the computation
        i + 1
      }
      # Ensure that the results array is in the same order as the input
      results.should eq((1..10).to_a)
    end
  end

  it("should parallelize computations (iterable)") do
    10.times do
      results = Zap::Utils::Parallel.parallelize(1..10) { |i|
        # Shuffle the fibers
        sleep(Random.rand(10).milliseconds)
        # Perform the computation
        i * 10
      }
      # Ensure that the results array is in the same order as the input
      results.should eq((10..100).step(10).to_a)
    end
  end

  it("should raise when one of the computation throws an exception") do
    parallel = Zap::Utils::Parallel(Int32).new(1..10) { |i|
      raise "error" if i == 5
      raise "unraised error" if i == 7
      i
    }
    expect_raises(Exception, "error") { parallel.await }
  end
end

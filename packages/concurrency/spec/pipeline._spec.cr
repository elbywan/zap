require "spec"
require "../pipeline"

describe Concurrency::Pipeline, tags: {"utils", "utils.concurrency"} do
  it "propagates errors from the processed blocks" do
    pipeline = Concurrency::Pipeline.new

    pipeline.process do
      raise "boom"
    end

    expect_raises(Concurrency::Pipeline::PipelineException, "boom") do
      pipeline.await
    end
  end

  it "respects the max fibers concurrency limit" do
    pipeline = Concurrency::Pipeline.new
    pipeline.set_concurrency(2)

    active = Atomic(Int32).new(0)
    max_active = Atomic(Int32).new(0)

    10.times do
      pipeline.process do
        current = active.add(1)
        max_active.max(current)
        sleep 0.01.seconds
        active.sub(1)
      end
    end

    pipeline.await
    max_active.get.should be <= 2
  end

  it "supports multiple phases on a reused pipeline" do
    pipeline = Concurrency::Pipeline.new

    # First phase completes and closes the end channel
    pipeline.process { 1 + 1 }
    pipeline.await

    # A second phase on the same pipeline must still deliver its errors
    # (regression: the closed channel used to make await return early and
    # the errors surfaced late, if at all)
    pipeline.process { raise "second phase boom" }
    expect_raises(Concurrency::Pipeline::PipelineException, "second phase boom") do
      pipeline.await
    end

    # And a clean second phase must not raise
    pipeline.process { 1 + 1 }
    pipeline.await
  end
end

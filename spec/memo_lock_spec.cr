require "./spec_helper"
require "../src/utils/memo_lock"

class MemoLocked
  include Zap::Utils::MemoLock(Int32)
end

module GloballyMemoLocked
  Zap::Utils::MemoLock::Global.memo_lock(:global, Int32)
end

describe Zap::Utils::MemoLock do
  it "should lock and memoize a block" do
    s = MemoLocked.new

    check = Atomic(Int32).new(0)
    results = Array(Int32).new(10, 0)
    chan = Channel(Nil).new(10)

    1..10.times do |i|
      spawn do
        results[i] = s.memo_lock("key") do
          10.times { Fiber.yield }
          check.add(1)
          i + 10
        end
      ensure
        chan.send(nil)
      end
    end
    1..10.times { chan.receive }
    # The computation should have been made only once
    check.get.should eq(1)
    # The result should be the same for all 10 fibers
    results.size.should eq(10)
    results.all? { |r| r == results[0] && r != 0 }.should be_true

    ############################

    check = Atomic(Int32).new(0)
    results = Array(Int32).new(10, 0)
    chan = Channel(Nil).new(10)

    1..10.times do |i|
      spawn do
        # Key is either 0 or 1
        results[i] = s.memo_lock((i % 2).to_s) do
          10.times { Fiber.yield }
          check.add(1)
          i
        end
      ensure
        chan.send(nil)
      end
    end
    1..10.times { chan.receive }
    # Since the key has 2 different values, the computation has been made twice
    check.get.should eq(2)
    sorted_results = results.sort
    results.sort.each_with_index do |r, i|
      if i < 5
        r.should eq(sorted_results[0])
      else
        r.should eq(sorted_results[5])
      end
    end
  end
end

describe Zap::Utils::MemoLock::Global do
  it "should lock and memoize a block" do
    check = Atomic(Int32).new(0)
    results = Array(Int32).new(10, 0)
    chan = Channel(Nil).new(10)

    1..10.times do |i|
      spawn do
        results[i] = GloballyMemoLocked.memo_lock_global("key") do
          10.times { Fiber.yield }
          check.add(1)
          i + 10
        end
      ensure
        chan.send(nil)
      end
    end
    1..10.times { chan.receive }
    # The computation should have been made only once
    check.get.should eq(1)
    # The result should be the same for all 10 fibers
    results.size.should eq(10)
    results.all? { |r| r == results[0] && r != 0 }.should be_true

    ############################

    check = Atomic(Int32).new(0)
    results = Array(Int32).new(10, 0)
    chan = Channel(Nil).new(10)

    1..10.times do |i|
      spawn do
        # Key is either 0 or 1
        results[i] = GloballyMemoLocked.memo_lock_global((i % 2).to_s) do
          10.times { Fiber.yield }
          check.add(1)
          i
        end
      ensure
        chan.send(nil)
      end
    end
    1..10.times { chan.receive }
    # Since the key has 2 different values, the computation has been made twice
    check.get.should eq(2)
    sorted_results = results.sort
    sorted_results.each_with_index do |r, i|
      if i < 5
        r.should eq(sorted_results[0])
      else
        r.should eq(sorted_results[5])
      end
    end
  end
end

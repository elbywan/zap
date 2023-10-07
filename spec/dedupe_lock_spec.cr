require "./spec_helper"
require "../src/utils/concurrent/dedupe_lock"

alias DedupeLock = ::Zap::Utils::Concurrent::DedupeLock

class Deduped
  include DedupeLock(Int32)
end

module GloballyDeduped
  DedupeLock::Global.setup(:global, Int32)
end

describe DedupeLock do
  it "should lock and memoize a block" do
    s = Deduped.new

    check = Atomic(Int32).new(0)
    results = Array(Int32).new(10, 0)
    chan = Channel(Nil).new(10)

    1..10.times do |i|
      spawn do
        results[i] = s.dedupe("key") do
          sleep 0.1.seconds
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
        results[i] = s.dedupe((i % 2).to_s) do
          sleep 0.1.seconds
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

describe DedupeLock::Global do
  it "should lock and memoize a block" do
    check = Atomic(Int32).new(0)
    results = Array(Int32).new(10, 0)
    chan = Channel(Nil).new(10)

    1..10.times do |i|
      spawn do
        results[i] = GloballyDeduped.dedupe_global("key") do
          sleep 0.1.seconds
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
        results[i] = GloballyDeduped.dedupe_global((i % 2).to_s) do
          sleep 0.1.seconds
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

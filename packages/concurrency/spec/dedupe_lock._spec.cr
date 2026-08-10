require "spec"
require "../dedupe_lock"

alias DedupeLock = Concurrency::DedupeLock

class Deduped
  include DedupeLock(Int32)
end

module GloballyDeduped
  DedupeLock::Global.setup(:global, Int32)
end

describe DedupeLock, tags: {"utils", "utils.concurrency"} do
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

  it "should retry when the producer fails" do
    s = Deduped.new

    attempts = Atomic(Int32).new(0)
    chan = Channel(Nil).new(2)
    results = Array(Int32).new
    errors = Array(Exception).new

    # The producer fails after letting the waiter attach to the channel
    spawn do
      begin
        s.dedupe("retry-key") do
          sleep 0.1.seconds
          attempts.add(1)
          raise "producer failure"
        end
      rescue ex
        errors << ex
      end
    ensure
      chan.send(nil)
    end

    # The waiter retries and becomes the producer
    spawn do
      begin
        results << s.dedupe("retry-key") do
          attempts.add(1)
          42
        end
      rescue ex
        errors << ex
      end
    ensure
      chan.send(nil)
    end

    2.times { chan.receive }
    # The producer failed, the waiter retried and produced the value
    errors.size.should eq(1)
    errors.first.message.should eq("producer failure")
    attempts.get.should eq(2)
    results.should eq([42])
  end

  it "should raise when the retries are exhausted" do
    s = Deduped.new

    chan = Channel(Nil).new(2)
    errors = Array(Exception).new

    # The producer fails after letting the waiter attach to the channel
    spawn do
      begin
        s.dedupe("limit-key") do
          sleep 0.1.seconds
          raise "producer failure"
        end
      rescue ex
        errors << ex
      end
    ensure
      chan.send(nil)
    end

    # The waiter is not allowed to retry
    spawn do
      begin
        s.dedupe("limit-key", max_retries: 0) do
          42
        end
      rescue ex
        errors << ex
      end
    ensure
      chan.send(nil)
    end

    2.times { chan.receive }
    errors.size.should eq(2)
    # The waiter's error is the producer's failure, not the generic message
    errors.all? { |e| e.message == "producer failure" }.should be_true
  end
end

describe DedupeLock::Global, tags: {"utils", "utils.concurrency"} do
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

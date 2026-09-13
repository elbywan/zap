require "./spec_helper"
require "../../install/timings"

module Commands::Install::Spec
  describe Timings do
    it "aggregates recorded and measured spans per phase" do
      Timings.enabled = true
      Timings.reset
      # Deterministic durations: the measured operation in between adds
      # microseconds, which cannot move the printed 0.1ms figures.
      Timings.record(Timings::Phase::MetadataParse.label, 5_000_000_i64)
      Timings.record(Timings::Phase::MetadataParse.label, 1_000_000_i64)
      value = Timings.measure(Timings::Phase::MetadataParse) { 42 }
      value.should eq(42)

      io = IO::Memory.new
      Timings.report(io)
      fields = io.to_s.lines.find(&.starts_with?("  metadata.parse")).not_nil!.split
      fields[1].should eq("3")        # count
      fields[2].should eq("6.0ms")    # total: 5ms + 1ms + the measured micros
      fields[3].should eq("2.000ms")  # mean
      fields[4].should eq("5.0ms")    # max: the slowest single operation
    ensure
      Timings.enabled = false
    end

    it "records nothing while disabled but still returns the block value" do
      Timings.enabled = false
      Timings.reset
      Timings.measure(Timings::Phase::MetadataParse) { 7 }.should eq(7)
      Timings.record(Timings::Phase::MetadataParse.label, 1_000_000_i64)

      io = IO::Memory.new
      Timings.report(io)
      io.to_s.lines.find(&.starts_with?("  metadata.parse")).not_nil!.split[1].should eq("0")
    end

    it "records failed operations too (the time was spent)" do
      Timings.enabled = true
      Timings.reset
      begin
        Timings.measure(Timings::Phase::TarballStore) { raise "boom" }
      rescue
        # expected
      end

      io = IO::Memory.new
      Timings.report(io)
      io.to_s.lines.find(&.starts_with?("  tarball.store")).not_nil!.split[1].should eq("1")
    ensure
      Timings.enabled = false
    end
  end
end

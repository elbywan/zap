# Aggregate per-phase timings, behind the --timings flag.
#
# Every phase is measured at its real call site with Time.monotonic and
# accumulated into atomics (relaxed ordering: counters only), so the
# numbers are exact sums across all worker threads — no sampling, no
# wall-clock guessing. Summed rows are aggregate work times and can
# exceed the wall clock when the phase ran concurrently; the .wall rows
# are sequential stage clocks measured once, encompassing everything
# nested inside them.
module Commands::Install::Timings
  # Summed work buckets (one record per operation).
  enum Phase
    MetadataFetch
    MetadataCacheRead
    MetadataCacheWrite
    MetadataParse
    PackageParse
    PackageCache
    TarballStore
    # The link phase: LinkItems is the sequential BFS per package, and
    # LinkBackend the synchronous part of the backend link call (the
    # per-package prepare, the store-tree crawl and the per-file dispatch
    # to the pipeline; the file I/O itself runs on the worker pool).
    LinkItems
    LinkBackend
    # The phase's single await: the dispatched link tasks draining on the
    # pool (the parallel I/O), after the sequential walk.
    LinkAwait
    # The tarball stream is a fused download+unpack: TarballUnpack covers
    # the whole unpack call, TarballNet the raw socket reads inside it, so
    # the difference is the inflate/tar/write CPU.
    TarballUnpack
    TarballNet

    def label : String
      case self
      in MetadataFetch      then "metadata.fetch"
      in MetadataCacheRead  then "metadata.cache_read"
      in MetadataCacheWrite then "metadata.cache_write"
      in MetadataParse      then "metadata.parse"
      in PackageParse       then "package.parse"
      in PackageCache       then "package.cache"
      in LinkItems          then "link.items"
      in LinkBackend        then "link.backend"
      in LinkAwait          then "link.await"
      in TarballStore       then "tarball.store"
      in TarballUnpack      then "tarball.unpack"
      in TarballNet         then "tarball.net"
      end
    end
  end

  # Sequential stage clocks (one record per install).
  enum Wall
    Resolve
    Link
    Hooks
    Total

    def label : String
      case self
      in Resolve then "resolve.wall"
      in Link    then "link.wall"
      in Hooks   then "hooks.wall"
      in Total   then "total.wall"
      end
    end
  end

  # A reference type on purpose: a struct would be copied out of the hash
  # on every lookup, sending the atomic adds to the copy.
  class Bucket
    getter total_ns = Atomic(Int64).new(0)
    getter count = Atomic(Int64).new(0)
    getter max_ns = Atomic(Int64).new(0)
  end

  class_property enabled : Bool = false

  @@buckets : Hash(String, Bucket) = begin
    buckets = Hash(String, Bucket).new
    Phase.each { |phase| buckets[phase.label] = Bucket.new }
    Wall.each { |wall| buckets[wall.label] = Bucket.new }
    buckets
  end

  def self.reset : Nil
    @@buckets.each_value do |bucket|
      bucket.total_ns.set(0, :relaxed)
      bucket.count.set(0, :relaxed)
      bucket.max_ns.set(0, :relaxed)
    end
  end

  def self.record(label : String, ns : Int64) : Nil
    return unless @@enabled
    return unless bucket = @@buckets[label]?
    bucket.total_ns.add(ns, :relaxed)
    bucket.count.add(1, :relaxed)
    bucket.max_ns.max(ns, :relaxed)
  end

  # The symbol entry point for the fetch shard's hook.
  def self.record(name : Symbol, ns : Int64) : Nil
    label = case name
            when :fetch   then Phase::MetadataFetch.label
            when :cache_r then Phase::MetadataCacheRead.label
            when :cache_w then Phase::MetadataCacheWrite.label
            when :parse   then Phase::MetadataParse.label
            else               return
            end
    record(label, ns)
  end

  # Measures and records the block; a no-op wrapper when disabled. The
  # block's value is returned either way. Failed operations are recorded
  # too (the time was spent regardless).
  def self.measure(label : String, &)
    return yield unless @@enabled
    t0 = Time.monotonic
    begin
      yield
    ensure
      record(label, (Time.monotonic - t0).total_nanoseconds.to_i64)
    end
  end

  def self.measure(phase : Phase, &)
    measure(phase.label) { yield }
  end

  def self.measure(wall : Wall, &)
    measure(wall.label) { yield }
  end

  # The report rows, in execution order: {label, indent}.
  ROWS = [
    {"resolve.wall", 0},
    {"metadata.fetch", 2},
    {"metadata.cache_read", 2},
    {"metadata.cache_write", 2},
    {"metadata.parse", 2},
    {"package.parse", 2},
    {"package.cache", 2},
    {"tarball.store", 2},
    {"tarball.unpack", 4},
    {"tarball.net", 6},
    {"link.wall", 0},
    {"link.items", 2},
    {"link.backend", 4},
    {"link.await", 2},
    {"hooks.wall", 0},
    {"total.wall", 0},
  ]

  def self.report(io : IO) : Nil
    total_wall = @@buckets["total.wall"].total_ns.get(:relaxed)
    io << "Timings (exact sums at the call sites; summed rows run concurrently, .wall rows are stage clocks)\n"
    io << "phase                              count       total      mean       max    wall%\n"
    ROWS.each do |(label, indent)|
      bucket = @@buckets[label]
      count = bucket.count.get(:relaxed)
      total_ns = bucket.total_ns.get(:relaxed)
      max_ns = bucket.max_ns.get(:relaxed)
      wall = label.ends_with?(".wall")
      io << (" " * indent) << label
      io << " " * Math.max(0, 32 - indent - label.size)
      io << count.to_s.rjust(6)
      io << ("%10.1fms" % (total_ns / 1_000_000.0)).rjust(12)
      io << ("%11.3fms" % (count > 0 ? total_ns / count / 1_000_000.0 : 0.0))
      # The slowest single operation exposes outliers hidden by the mean
      # (summed rows); wall rows are single measurements, so the max is
      # the total there and the wall share is the informative figure.
      if wall
        io << " " * 11
        io << ("%8.1f%%" % (total_wall > 0 ? total_ns * 100.0 / total_wall : 0.0))
      else
        io << ("%10.1fms" % (max_ns / 1_000_000.0)).rjust(11)
        io << " " * 8
      end
      io << "\n"
    end
  end

  def self.report_file(path : String) : Nil
    File.open(path, "w") { |file| report(file) }
  end

  # Times the raw reads of the stream it wraps — the socket-level reads of
  # a tarball download — so the network wait inside an unpack can be told
  # apart from the inflate/tar/write CPU. Install it *below* IO::Digest:
  # the digest's own work then stays in the unpack residual.
  class TimingIO < IO
    def initialize(@io : IO, @label : String)
    end

    def read(slice : Bytes) : Int32
      t0 = Time.monotonic
      begin
        @io.read(slice)
      ensure
        Timings.record(@label, (Time.monotonic - t0).total_nanoseconds.to_i64)
      end
    end

    def write(slice : Bytes) : Nil
      @io.write(slice)
    end

    def close : Nil
      @io.close
    end

    def closed? : Bool
      @io.closed?
    end
  end
end

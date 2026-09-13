module Commands::Install
  # The declared range of every dependency edge that resolved fresh during
  # this run, keyed by "<parent key>\u0000<dependency name>".
  #
  # A class, not a struct: `State` is a record, so a struct field would be
  # copied with it and the copy would carry its own lock while sharing the
  # map — the recording happens inside the resolution fibers, so the
  # synchronization must survive any copy.
  class EdgeRanges
    def initialize
      @ranges = Hash(String, String).new
      @lock = Mutex.new
    end

    def []=(key : String, range : String) : Nil
      @lock.synchronize { @ranges[key] = range }
    end

    def empty? : Bool
      @lock.synchronize { @ranges.empty? }
    end

    # The edges in a fixed order, so the collapse pass is deterministic.
    def each_sorted(& : String, String ->) : Nil
      edges = @lock.synchronize { @ranges.to_a.sort_by!(&.[0]) }
      edges.each { |(key, range)| yield key, range }
    end
  end
end

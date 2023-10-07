struct Zap::Utils::Concurrent::Parallel(T)
  def initialize(@size : Int32, &block : Int32 -> T)
    @channel = Channel({Int32, T} | Exception).new
    @size.times do |i|
      compute(i, i, &block)
    end
  end

  def initialize(iterable : Iterable(U), &block : U -> T) forall U
    @size = iterable.size
    @channel = Channel({Int32, T} | Exception).new
    iterable.each_with_index do |item, index|
      compute(item, index, &block)
    end
  end

  private def compute(arg : U, index : Int32, &block : U -> T) forall U
    spawn do
      begin
        @channel.send({index, block.call(arg)})
      rescue Channel::ClosedError
        # ignore
      rescue ex
        begin
          @channel.send(ex)
        rescue Channel::ClosedError
          # ignore
        end
      end
    end
  end

  def await : Array(T)
    results = Array(T).new(@size) { _t = uninitialized T }
    @size.times do
      result = @channel.receive
      raise result if result.is_a?(Exception)
      index, value = result
      results[index] = value
    end
    results
  ensure
    @channel.close
  end

  def self.parallelize(iterable : Iterable(U), &block : U -> T) forall U
    new(iterable, &block).await
  end

  def self.parallelize(size : Int32, &block : Int32 -> T)
    new(size, &block).await
  end
end

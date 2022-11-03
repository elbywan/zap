class Pipeline
  getter counter = 0
  getter progress = 0
  getter max = 0
  @mutex = Mutex.new
  @end_channel : Channel(Nil) = Channel(Nil).new

  def initialize
  end

  def process(&block)
    @mutex.synchronize do
      @counter += 1
      @max += 1
    end
    spawn do
      block.call
    ensure
      @mutex.synchronize do
        @counter -= 1
        p "#{@progress += 1} / #{max}"
        @end_channel.send(nil) if @counter == 0
      end
    end
  end

  def await
    @end_channel.receive
  end
end

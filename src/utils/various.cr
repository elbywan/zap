module Zap::Utils::Various
  def self.parse_key(raw_key : String)
    split_key = raw_key.split('@')
    if raw_key.starts_with?("@")
      name = split_key[0..1].join('@')
      version = split_key[2]?
    else
      name = split_key.first
      version = split_key[1]?
    end
    return name, version
  end

  def self.format_time_span(span : Time::Span)
    String.build do |str|
      format_time_span(str, span)
    end
  end

  def self.format_time_span(io : IO, span : Time::Span)
    less_than_a_milli = true
    if span.hours > 0
      less_than_a_milli = false
      io << "#{span.hours}h"
    end
    if span.minutes > 0
      less_than_a_milli = false
      io << "#{span.minutes}m"
    end
    if span.seconds > 0
      less_than_a_milli = false
      io << "#{span.seconds}s"
    elsif span.milliseconds > 0
      less_than_a_milli = false
      io << "#{span.milliseconds}ms"
    end
    if less_than_a_milli
      io << "0ms"
    end
  end

  class STDOUTSync < IO
    def initialize
      @mutex = Mutex.new
      @stdout = STDOUT
    end

    def read(slice : Bytes)
      @stdout.read(slice)
    end

    def write(slice : Bytes) : Nil
      @mutex.synchronize do
        @stdout.write(slice)
      end
    end
  end
end

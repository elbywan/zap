require "log"
require "colorize"

struct Zap::Debug::Formatter < ::Log::StaticFormatter
  record SourceData, color : Colorize::Color256 | Symbol, timestamp : Time::Span? = nil
  @@sources = Hash(String, SourceData).new

  def run
    source = @entry.source
    string "\r"
    if source
      source_data = @@sources[source]?
      source_color = source_data.try &.color || COLORS[@@sources.size % COLORS.size]
      source_time = source_data.try { |data| data.timestamp ? (Time.monotonic - data.timestamp.not_nil!) : nil } || 0.milliseconds
      unless source_data
        source_color = COLORS[@@sources.size % COLORS.size]
        source_data = SourceData.new(COLORS[@@sources.size % COLORS.size], Time.monotonic)
        @@sources[source] = source_data
      else
        @@sources[source] = source_data.copy_with(timestamp: Time.monotonic)
      end
      @io << source.ljust(15).colorize(source_color).bold
    end
    string " "
    @io << @entry.severity.label.rjust(6).colorize.blue
    string " ".colorize.dim
    @io << @entry.timestamp.to_s("%H:%M:%S.%L").colorize.dim
    if source_time
      string " "
      string "+#{Utils::Various.format_time_span(source_time)}".rjust(6).colorize(:light_magenta).dim
    end
    string " - "
    message
    data(before: " -- ")
    context(before: " -- ")
    exception
  end
end

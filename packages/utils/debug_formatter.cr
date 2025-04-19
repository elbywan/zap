require "log"
require "colorize"
require "shared/constants"
require "./misc"

struct Utils::DebugFormatter < ::Log::StaticFormatter
  record SourceData, color : Colorize::Color256 | Symbol, timestamp : Time::Span? = nil
  @@sources = Hash(String, SourceData).new

  def run
    source = @entry.source
    string "\r"
    if source
      source_data = @@sources[source]?
      source_color = source_data.try &.color || Shared::Constants::COLORS[@@sources.size % Shared::Constants::COLORS.size]
      source_time = source_data.try { |data| data.timestamp ? (Time.monotonic - data.timestamp.not_nil!) : nil } || 0.milliseconds
      unless source_data
        source_color = Shared::Constants::COLORS[@@sources.size % Shared::Constants::COLORS.size]
        source_data = SourceData.new(Shared::Constants::COLORS[@@sources.size % Shared::Constants::COLORS.size], Time.monotonic)
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
      color = source_time < 0.1.seconds ? :light_magenta : source_time < 0.25.seconds ? :light_green : (source_time < 1.seconds ? :light_yellow : :light_red)
      string " "
      string "+#{Utils::Misc.format_time_span(source_time)}".rjust(6).colorize(color).dim
    end
    string " - "
    message
    data(before: " -- ")
    context(before: " -- ")
    exception
  end
end

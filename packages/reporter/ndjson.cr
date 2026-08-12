require "json"
require "log"
require "utils/timers"
require "./interactive"

# Emits newline-delimited JSON events for machine consumers
# (pnpm --reporter=ndjson parity): one object per line, no ANSI, no colors.
# Progress events every few seconds once a phase is slow, then
# info/warning/error events as they happen, and a final done event with
# the summary counts.
class Reporter::Ndjson < Reporter::Interactive
  def initialize(@out = STDOUT)
    Colorize.enabled = false
    super
  end

  def report_resolver_updates(& : -> T) : T forall T
    @stopped = false
    @last_progress = Time.monotonic
    @action = -> do
      progress("resolving", @resolved_packages.get, @resolving_packages.get)
    end
    yield
  ensure
    self.stop
  end

  def report_linker_updates(& : -> T) : T forall T
    @stopped = false
    @last_progress = Time.monotonic
    @action = -> do
      progress("installing", @installed_packages.get, @installing_packages.get)
    end
    yield
  ensure
    self.stop
  end

  def report_builder_updates(& : -> T) : T forall T
    @stopped = false
    @last_progress = Time.monotonic
    @action = -> do
      progress("building", @built_packages.get, @building_packages.get)
    end
    yield
  ensure
    self.stop
  end

  def report_done(realtime, memory, install_config, *, unmet_peers : Hash(String, Hash(Semver::Range, Set(String)))? = nil) : Nil
    if install_config.print_logs
      @logs.each do |log|
        emit { |json| json.field("type", "warning"); json.field("message", log) }
      end
    end
    if unmet_peers && !unmet_peers.empty?
      peers = unmet_peers.to_a.flat_map do |name, versions|
        versions.map { |range, peers| "#{name}@#{range} (#{peers.join(", ")})" }
      end
      emit { |json| json.field("type", "unmet_peers"); json.field("peers", peers) }
    end
    emit do |json|
      json.field("type", "done")
      json.field("resolved", @resolved_packages.get)
      json.field("installed", @installed_packages.get)
      json.field("added", @added_packages.size)
      json.field("removed", @removed_packages.size)
      json.field("duration_ms", realtime.total_milliseconds.to_i64)
    end
  end

  def info(str : String) : Nil
    emit { |json| json.field("type", "info"); json.field("message", str) }
  end

  def warning(error : Exception, location : String? = "") : Nil
    emit do |json|
      json.field("type", "warning")
      json.field("message", error.message)
      json.field("location", location) unless location.empty?
    end
  end

  def error(error : Exception, location : String? = "") : Nil
    emit do |json|
      json.field("type", "error")
      json.field("message", error.message)
      json.field("location", location) unless location.empty?
    end
  end

  def errors(errors : Array({Exception, String})) : Nil
    errors.each do |(_, message)|
      emit { |json| json.field("type", "error"); json.field("message", message) }
    end
  end

  # Script output and hook headers are human-readable; drop them so the
  # stream stays pure JSON (the child processes are redirected to a null
  # sink by the script printers).
  def output : IO
    NULL_IO
  end

  def output_sync(&block : IO ->) : Nil
    block.call(NULL_IO)
  end

  def prepend(bytes : Bytes) : Nil
  end

  private def progress(phase : String, done : Int32, total : Int32) : Nil
    return unless progress_due?
    emit do |json|
      json.field("type", "progress")
      json.field("phase", phase)
      json.field("done", done)
      json.field("total", total)
    end
  end

  private class NullIO < IO
    def read(slice : Bytes) : Int32
      0
    end

    def write(slice : Bytes) : Nil
    end
  end

  private NULL_IO = NullIO.new

  private def emit(& : JSON::Builder ->) : Nil
    @io_lock.synchronize do
      JSON.build(@out) do |json|
        json.object do
          yield json
        end
      end
      @out << Shared::Constants::NEW_LINE
      @out.flush
    end
  end
end

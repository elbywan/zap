require "shared/constants"
require "concurrency/mutex"

abstract class Reporter
  Log = ::Log.for("zap.reporter")
  getter io_lock = Concurrency::Mutex.new

  abstract def output : IO
  abstract def output_sync(&block : IO ->) : Nil
  abstract def on_resolving_package : Nil
  abstract def on_package_resolved : Nil
  abstract def on_downloading_package : Nil
  abstract def on_package_downloaded : Nil
  abstract def on_packing_package : Nil
  abstract def on_package_packed : Nil
  abstract def on_package_linked : Nil
  abstract def on_linking_package : Nil
  abstract def on_package_built : Nil
  abstract def on_building_package : Nil
  abstract def on_package_added(pkg_key : String) : Nil
  abstract def on_package_removed(pkg_key : String) : Nil
  abstract def stop : Nil
  abstract def info(str : String) : Nil
  abstract def warning(error : Exception, location : String?) : Nil
  abstract def error(error : Exception, location : String?) : Nil
  abstract def errors(errors : Array({Exception, String})) : Nil
  abstract def prepend(bytes : Bytes) : Nil
  abstract def log(str : String) : Nil
  abstract def report_resolver_updates(& : -> T) forall T
  abstract def report_linker_updates(& : -> T) forall T
  abstract def report_builder_updates(& : -> T) forall T
  abstract def report_done(realtime, memory, install_config, *, unmet_peers : Hash(String, Hash(Semver::Range, Set(String)))? = nil) : Nil
  abstract def header(emoji : String, str : String, color = :default) : String

  class ReporterPrependPipe < IO
    def initialize(@reporter : Reporter)
    end

    def read(slice : Bytes)
      raise "Cannot read from a pipe"
    end

    def write(slice : Bytes) : Nil
      @reporter.prepend(slice)
    end
  end

  class ReporterFormattedAppendPipe < IO
    def initialize(@reporter : Reporter, @separator = Shared::Constants::NEW_LINE, @prefix = "     ")
      @separator_and_prefix = @separator + @prefix
    end

    def read(slice : Bytes)
      raise "Cannot read from a pipe"
    end

    def write(slice : Bytes) : Nil
      @reporter.output_sync do |output|
        str_array = String.new(slice).split(@separator)
        str_array.pop if str_array.last.empty?
        output << @prefix << str_array.join(@separator_and_prefix) << @separator
      end
    end
  end
end

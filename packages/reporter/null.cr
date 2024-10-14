require "./reporter"

class Reporter::Null < Reporter
  @out : IO

  def initialize
    @out = File.open(File::NULL, "w")
  end

  def output : IO
    @out
  end

  def output_sync(&block : IO ->) : Nil
    yield @out
  end

  def on_resolving_package : Nil
    # noop
  end

  def on_package_resolved : Nil
    # noop
  end

  def on_downloading_package : Nil
    # noop
  end

  def on_package_downloaded : Nil
    # noop
  end

  def on_packing_package : Nil
    # noop
  end

  def on_package_packed : Nil
    # noop
  end

  def on_package_linked : Nil
    # noop
  end

  def on_linking_package : Nil
    # noop
  end

  def on_package_built : Nil
    # noop
  end

  def on_building_package : Nil
    # noop
  end

  def on_package_added(pkg_key : String) : Nil
    # noop
  end

  def on_package_removed(pkg_key : String) : Nil
    # noop
  end

  def stop : Nil
    # noop
  end

  def info(str : String) : Nil
    # noop
  end

  def warning(error : Exception, location : String? = "") : Nil
    # noop
  end

  def error(error : Exception, location : String? = "") : Nil
    # noop
  end

  def errors(errors : Array({Exception, String})) : Nil
    # noop
  end

  def prepend(bytes : Bytes) : Nil
    # noop
  end

  def log(str : String) : Nil
    # noop
  end

  def report_resolver_updates(& : -> T) : T forall T
    yield # noop
  end

  def report_linker_updates(& : -> T) : T forall T
    yield # noop
  end

  def report_builder_updates(& : -> T) : T forall T
    yield # noop
  end

  def report_done(realtime, memory, install_config, *, unmet_peers : Hash(String, Hash(Semver::Range, Set(String)))? = nil) : Nil
    # noop
  end

  def header(emoji : String, str : String, color = :default) : String
    ""
  end
end

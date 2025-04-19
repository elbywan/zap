require "./reporter"

class Reporter::Proxy < Reporter
  getter parent : Reporter

  def initialize(@parent : Reporter)
  end

  def output : IO
    parent.output
  end

  def output_sync(&block : IO ->) : Nil
    parent.output_sync do |io|
      block.call(io)
    end
  end

  def on_resolving_package : Nil
    parent.on_resolving_package
  end

  def on_package_resolved : Nil
    parent.on_package_resolved
  end

  def on_downloading_package : Nil
    parent.on_downloading_package
  end

  def on_package_downloaded : Nil
    parent.on_package_downloaded
  end

  def on_packing_package : Nil
    parent.on_packing_package
  end

  def on_package_packed : Nil
    parent.on_package_packed
  end

  def on_package_linked : Nil
    parent.on_package_linked
  end

  def on_linking_package : Nil
    parent.on_linking_package
  end

  def on_package_built : Nil
    parent.on_package_built
  end

  def on_building_package : Nil
    parent.on_building_package
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
    parent.info(str)
  end

  def warning(error : Exception, location : String? = "") : Nil
    parent.warning(error, location)
  end

  def error(error : Exception, location : String? = "") : Nil
    parent.error(error, location)
  end

  def errors(errors : Array({Exception, String})) : Nil
    parent.errors(errors)
  end

  def prepend(bytes : Bytes) : Nil
    parent.prepend(bytes)
  end

  def log(str : String) : Nil
    parent.log(str)
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

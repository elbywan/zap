require "utils/macros"
require "core/command_config"

struct Commands::Catalog::Config < Core::CommandConfig
  Utils::Macros.record_utils

  enum CatalogAction
    List
    Add
    Remove
  end

  getter action : CatalogAction
  # The catalog edited or listed: the default catalog by default.
  getter catalog : String = "default"
  getter args : Array(String) = Array(String).new

  def from_args(args : Array(String))
    copy_with(args: args)
  end
end

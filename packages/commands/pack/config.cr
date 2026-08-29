require "utils/macros"
require "core/command_config"

struct Commands::Pack::Config < Core::CommandConfig
  Utils::Macros.record_utils

  # The directory to pack (default: the project prefix).
  getter path : String? = nil
  # The archive output path; %s and %v are replaced by the package name
  # and version (default: package.tgz in the package directory).
  @[Env]
  getter output : String? = nil
end

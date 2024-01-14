module Zap
  NEW_LINE = '\n'

  enum ErrorCodes : Int32
    EARLY_EXIT             = 1
    INSTALL_COMMAND_FAILED
    RESOLVER_ERROR
    INSTALLER_ERROR
  end

  COLORS = {
    # IndianRed1
    Colorize::Color256.new(203),
    # DeepSkyBlue2
    Colorize::Color256.new(38),
    # Chartreuse3
    Colorize::Color256.new(76),
    # LightGoldenrod1
    Colorize::Color256.new(220),
    # MediumVioletRed
    Colorize::Color256.new(126),
    :light_gray,
    :blue,
    :light_red,
    :light_green,
    :yellow,
    :dark_gray,
    :cyan,
    :red,
    :green,
    :light_yellow,
    :magenta,
    :light_blue,
    :light_cyan,
    :light_magenta,
  }

  GH_URL_REGEX   = /^https:\/\/github.com\/(?P<owner>[a-zA-Z0-9\-_]+)\/(?P<package>[^#^\/]+)(?:#(?P<hash>[.*]))?/
  GH_SHORT_REGEX = /^[^@.\/][^\/]+\/[^\/]+$/

  # See: https://github.com/npm/registry/blob/master/docs/responses/package-metadata.md#package-metadata
  ACCEPT_HEADER = "application/vnd.npm.install-v1+json; q=1.0, application/json; q=0.8, */*"
  HEADERS       = HTTP::Headers{"Accept" => ACCEPT_HEADER}
end

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
end

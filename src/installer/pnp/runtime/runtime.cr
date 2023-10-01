module Zap::Installer::PnP::Runtime
  CJS = {{ read_file("#{__DIR__}/.pnp.cjs") }}
  MJS = {{ read_file("#{__DIR__}/.pnp.loader.mjs") }}
end

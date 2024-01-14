require "./dlx"
require "./exec"
require "./init"
require "./install"
require "./rebuild"
require "./run"
require "./store"
require "./why"

module Zap::Commands
  Log = Zap::Log.for(self)
end

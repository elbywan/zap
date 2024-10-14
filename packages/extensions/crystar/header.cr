require "crystar"

module Crystar
  class Header
    property uid : Int64
    property gid : Int64

    def uid=(v : Int)
      @uid = v.to_i64
    end

    def gid=(v : Int)
      @gid = v.to_i64
    end
  end
end

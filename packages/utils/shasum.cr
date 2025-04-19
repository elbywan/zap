require "digest"
require "openssl/digest"

class Shasum < IO
  delegate final, hexfinal, to: @digest_algorithm

  def initialize(@digest_algorithm : ::Digest)
  end

  def read(slice : Bytes) : Int32
    0
  end

  def write(slice : Bytes) : Nil
    return if slice.empty?

    @digest_algorithm.update(slice)
  end
end

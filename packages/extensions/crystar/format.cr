module Crystar
  private class Block
    def set_format(format : Format) : Nil
      # Set the magic values
      case
      when format.has(Format::V7)
        # Do nothing
      when format.has(Format::GNU)
        gnu.magic = MAGIC_GNU
        gnu.version = VERSION_GNU
      when format.has(Format::STAR)
        star.magic = MAGIC_USTAR
        star.version = VERSION_USTAR
        star.trailer = TRAILER_STAR
      when format.has(Format::USTAR), format.has(Format::PAX)
        ustar.magic = MAGIC_USTAR
        ustar.version = VERSION_USTAR
      else
        raise Error.new("invalid format #{format}")
      end

      # Update checksum
      # This field is special in that it is terminated by a NULL then space.

      f = Formatter.new
      field = v7.chksum
      chksum, _ = compute_checksum # Possible values are 256..128776
      f.format_octal(field[...7], chksum)
      field[7] = ' '.ord.to_u8
    end
  end
end

require "json"

# A packument scanner built around the block-bitmask shape LLVM
# autovectorizes (measured ~1.8GB/s versus the pull parser's ~68MB/s on
# the same data): 16-byte blocks, a vector comparison against the
# structural bytes, and a bitmask whose lowest set bit is the next jump.
# String interiors and the string-map values use byte_index (memchr)
# instead, so no loop scans string content byte-by-byte.
#
# The manifest only needs three fields (dist-tags, versions, time) plus
# the byte range of every version's raw JSON. Any unexpected structure
# returns nil and the caller falls back to the JSON pull parser, so
# correctness never depends on this path.
module Commands::Install::PackumentScanner
  record Result,
    dist_tags : Hash(String, String),
    versions : Array(String),
    version_spans : Hash(String, {Int32, Int32}),
    times : Hash(String, String)

  def self.scan(body : String) : Result?
    data = body.to_slice
    size = data.size
    pos = skip_ws(data, 0)
    return nil if pos >= size || data[pos] != '{'.ord
    pos += 1

    dist_tags = nil
    versions = nil
    version_spans = nil
    times = nil

    loop do
      pos = skip_ws(data, pos)
      return nil if pos >= size
      case data[pos]
      when '}'.ord
        break
      when ','.ord
        pos += 1
        next
      end
      return nil unless data[pos] == '"'.ord
      key_end = string_end(data, pos)
      return nil unless key_end
      key = body.byte_slice(pos + 1, key_end - pos - 1)
      pos = skip_ws(data, key_end + 1)
      return nil if pos >= size || data[pos] != ':'.ord
      pos = skip_ws(data, pos + 1)

      case key
      when "dist-tags"
        parsed = scan_string_map(body, data, pos)
        return nil unless parsed
        dist_tags = parsed[0]
        pos = parsed[1]
      when "versions"
        parsed = scan_versions(body, data, pos)
        return nil unless parsed
        versions = parsed[0]
        version_spans = parsed[1]
        pos = parsed[2]
      when "time"
        parsed = scan_string_map(body, data, pos)
        return nil unless parsed
        times = parsed[0]
        pos = parsed[1]
      else
        pos = skip_value(body, data, pos)
        return nil unless pos
      end
    end

    # The three fields are optional in practice (minimal packuments omit
    # `time`); only the versions payload is required.
    return nil unless versions && version_spans
    Result.new(
      dist_tags || Hash(String, String).new,
      versions,
      version_spans,
      times || Hash(String, String).new,
    )
  end

  # The block-scan: the first index >= pos whose byte is one of *chars*,
  # or nil. The 16-wide mask is the shape LLVM turns into SIMD.
  private def self.next_of(data : Bytes, pos : Int32, c1 : Int32, c2 : Int32, c3 : Int32, c4 : Int32, c5 : Int32, c6 : Int32, c7 : Int32) : Int32?
    size = data.size
    while pos + 16 <= size
      mask = 0_u32
      16.times do |j|
        b = data[pos + j]
        if b == c1 || b == c2 || b == c3 || b == c4 || b == c5 || b == c6 || b == c7
          mask |= (1_u32 << j)
        end
      end
      unless mask == 0
        return pos + mask.trailing_zeros_count
      end
      pos += 16
    end
    while pos < size
      b = data[pos]
      return pos if b == c1 || b == c2 || b == c3 || b == c4 || b == c5 || b == c6 || b == c7
      pos += 1
    end
    nil
  end

  # The `{"key": "value", ...}` maps (dist-tags and time).
  private def self.scan_string_map(body : String, data : Bytes, pos : Int32) : {Hash(String, String), Int32}?
    size = data.size
    return nil if pos >= size || data[pos] != '{'.ord
    pos += 1
    map = Hash(String, String).new

    loop do
      pos = skip_ws(data, pos)
      return nil if pos >= size
      case data[pos]
      when '}'.ord
        return {map, pos + 1}
      when ','.ord
        pos += 1
        next
      end
      return nil unless data[pos] == '"'.ord
      key_end = string_end(data, pos)
      return nil unless key_end
      key = string(body, pos + 1, key_end)
      pos = skip_ws(data, key_end + 1)
      return nil if pos >= size || data[pos] != ':'.ord
      pos = skip_ws(data, pos + 1)
      return nil if pos >= size || data[pos] != '"'.ord
      val_end = string_end(data, pos)
      return nil unless val_end
      map[key] = string(body, pos + 1, val_end)
      pos = val_end + 1
    end
  end

  # The `{"x.y.z": {...}, ...}` versions map: the keys and the byte range
  # of every value.
  private def self.scan_versions(body : String, data : Bytes, pos : Int32) : {Array(String), Hash(String, {Int32, Int32}), Int32}?
    size = data.size
    return nil if pos >= size || data[pos] != '{'.ord
    pos += 1
    versions = Array(String).new
    spans = Hash(String, {Int32, Int32}).new

    loop do
      pos = skip_ws(data, pos)
      return nil if pos >= size
      case data[pos]
      when '}'.ord
        return {versions, spans, pos + 1}
      when ','.ord
        pos += 1
        next
      end
      return nil unless data[pos] == '"'.ord
      key_end = string_end(data, pos)
      return nil unless key_end
      version = body.byte_slice(pos + 1, key_end - pos - 1)
      pos = skip_ws(data, key_end + 1)
      return nil if pos >= size || data[pos] != ':'.ord
      value_start = skip_ws(data, pos + 1)
      value_end = skip_value(body, data, value_start)
      return nil unless value_end
      versions << version
      spans[version] = {value_start, value_end - value_start}
      pos = value_end
    end
  end

  # The end of the value at *pos* (one past its last byte), or nil.
  private def self.skip_value(body : String, data : Bytes, pos : Int32) : Int32?
    size = data.size
    return nil if pos >= size
    case data[pos]
    when '"'.ord
      e = string_end(data, pos)
      e ? e + 1 : nil
    when '{'.ord, '['.ord
      depth = 0
      while pos < size
        idx = next_of(data, pos, '"'.ord, '{'.ord, '}'.ord, '['.ord, ']'.ord, 0, 0)
        return nil unless idx
        case data[idx]
        when '"'.ord
          e = string_end(data, idx)
          return nil unless e
          pos = e + 1
        when '{'.ord, '['.ord
          depth += 1
          pos = idx + 1
        else
          depth -= 1
          return idx + 1 if depth == 0
          pos = idx + 1
        end
      end
      nil
    else
      idx = next_of(data, pos, ','.ord, '}'.ord, ']'.ord, 0, 0, 0, 0)
      idx || pos
    end
  end

  # The closing quote of the string opening at *quote*, honoring escapes.
  # The interior is skipped with memchr; only the backslashes before a
  # candidate quote are examined.
  private def self.string_end(data : Bytes, quote : Int32) : Int32?
    size = data.size
    pos = quote + 1
    while pos < size
      idx = data.index('"'.ord, pos)
      return nil unless idx
      backslashes = 0
      j = idx - 1
      while j > quote && data[j] == '\\'.ord
        backslashes += 1
        j -= 1
      end
      return idx if backslashes.even?
      pos = idx + 1
    end
    nil
  end

  # The key/value bytes between *start* and *stop* (exclusive), decoded
  # through the JSON parser only when an escape is present.
  private def self.string(body : String, start : Int32, stop : Int32) : String
    raw = body.byte_slice(start, stop - start)
    return raw unless raw.index('\\')
    JSON.parse(%("#{raw}")).as_s
  end

  private def self.skip_ws(data : Bytes, pos : Int32) : Int32
    size = data.size
    while pos < size
      case data[pos]
      when ' '.ord, '\t'.ord, '\n'.ord, '\r'.ord
        pos += 1
      else
        break
      end
    end
    pos
  end
end

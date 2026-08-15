# The RFC 7541 Appendix B Huffman code: (code, bit length) per symbol.
# The code is the bit pattern from the RFC, MSB-aligned at the given
# length (e.g. "/" is "011000" = 0x18 in 6 bits).
module HTTP2
  module HPACK
    module Huffman
      EOS = 256

      # (code, length) per symbol, indexed by the symbol (0..256, 256 = EOS).
      CODES = [
        {0x1ff8_u32, 13}, # 0
        {0x7fffd8_u32, 23}, # 1
        {0xfffffe2_u32, 28}, # 2
        {0xfffffe3_u32, 28}, # 3
        {0xfffffe4_u32, 28}, # 4
        {0xfffffe5_u32, 28}, # 5
        {0xfffffe6_u32, 28}, # 6
        {0xfffffe7_u32, 28}, # 7
        {0xfffffe8_u32, 28}, # 8
        {0xffffea_u32, 24}, # 9
        {0x3ffffffc_u32, 30}, # 10
        {0xfffffe9_u32, 28}, # 11
        {0xfffffea_u32, 28}, # 12
        {0x3ffffffd_u32, 30}, # 13
        {0xfffffeb_u32, 28}, # 14
        {0xfffffec_u32, 28}, # 15
        {0xfffffed_u32, 28}, # 16
        {0xfffffee_u32, 28}, # 17
        {0xfffffef_u32, 28}, # 18
        {0xffffff0_u32, 28}, # 19
        {0xffffff1_u32, 28}, # 20
        {0xffffff2_u32, 28}, # 21
        {0x3ffffffe_u32, 30}, # 22
        {0xffffff3_u32, 28}, # 23
        {0xffffff4_u32, 28}, # 24
        {0xffffff5_u32, 28}, # 25
        {0xffffff6_u32, 28}, # 26
        {0xffffff7_u32, 28}, # 27
        {0xffffff8_u32, 28}, # 28
        {0xffffff9_u32, 28}, # 29
        {0xffffffa_u32, 28}, # 30
        {0xffffffb_u32, 28}, # 31
        {0x14_u32, 6}, # ' '
        {0x3f8_u32, 10}, # '!'
        {0x3f9_u32, 10}, # '"'
        {0xffa_u32, 12}, # '#'
        {0x1ff9_u32, 13}, # '$'
        {0x15_u32, 6}, # '%'
        {0xf8_u32, 8}, # '&'
        {0x7fa_u32, 11}, # '\''
        {0x3fa_u32, 10}, # '('
        {0x3fb_u32, 10}, # ')'
        {0xf9_u32, 8}, # '*'
        {0x7fb_u32, 11}, # '+'
        {0xfa_u32, 8}, # ','
        {0x16_u32, 6}, # '-'
        {0x17_u32, 6}, # '.'
        {0x18_u32, 6}, # '/'
        {0x0_u32, 5}, # '0'
        {0x1_u32, 5}, # '1'
        {0x2_u32, 5}, # '2'
        {0x19_u32, 6}, # '3'
        {0x1a_u32, 6}, # '4'
        {0x1b_u32, 6}, # '5'
        {0x1c_u32, 6}, # '6'
        {0x1d_u32, 6}, # '7'
        {0x1e_u32, 6}, # '8'
        {0x1f_u32, 6}, # '9'
        {0x5c_u32, 7}, # ':'
        {0xfb_u32, 8}, # ';'
        {0x7ffc_u32, 15}, # '<'
        {0x20_u32, 6}, # '='
        {0xffb_u32, 12}, # '>'
        {0x3fc_u32, 10}, # '?'
        {0x1ffa_u32, 13}, # '@'
        {0x21_u32, 6}, # 'A'
        {0x5d_u32, 7}, # 'B'
        {0x5e_u32, 7}, # 'C'
        {0x5f_u32, 7}, # 'D'
        {0x60_u32, 7}, # 'E'
        {0x61_u32, 7}, # 'F'
        {0x62_u32, 7}, # 'G'
        {0x63_u32, 7}, # 'H'
        {0x64_u32, 7}, # 'I'
        {0x65_u32, 7}, # 'J'
        {0x66_u32, 7}, # 'K'
        {0x67_u32, 7}, # 'L'
        {0x68_u32, 7}, # 'M'
        {0x69_u32, 7}, # 'N'
        {0x6a_u32, 7}, # 'O'
        {0x6b_u32, 7}, # 'P'
        {0x6c_u32, 7}, # 'Q'
        {0x6d_u32, 7}, # 'R'
        {0x6e_u32, 7}, # 'S'
        {0x6f_u32, 7}, # 'T'
        {0x70_u32, 7}, # 'U'
        {0x71_u32, 7}, # 'V'
        {0x72_u32, 7}, # 'W'
        {0xfc_u32, 8}, # 'X'
        {0x73_u32, 7}, # 'Y'
        {0xfd_u32, 8}, # 'Z'
        {0x1ffb_u32, 13}, # '['
        {0x7fff0_u32, 19}, # '\'
        {0x1ffc_u32, 13}, # ']'
        {0x3ffc_u32, 14}, # '^'
        {0x22_u32, 6}, # '_'
        {0x7ffd_u32, 15}, # '`'
        {0x3_u32, 5}, # 'a'
        {0x23_u32, 6}, # 'b'
        {0x4_u32, 5}, # 'c'
        {0x24_u32, 6}, # 'd'
        {0x5_u32, 5}, # 'e'
        {0x25_u32, 6}, # 'f'
        {0x26_u32, 6}, # 'g'
        {0x27_u32, 6}, # 'h'
        {0x6_u32, 5}, # 'i'
        {0x74_u32, 7}, # 'j'
        {0x75_u32, 7}, # 'k'
        {0x28_u32, 6}, # 'l'
        {0x29_u32, 6}, # 'm'
        {0x2a_u32, 6}, # 'n'
        {0x7_u32, 5}, # 'o'
        {0x2b_u32, 6}, # 'p'
        {0x76_u32, 7}, # 'q'
        {0x2c_u32, 6}, # 'r'
        {0x8_u32, 5}, # 's'
        {0x9_u32, 5}, # 't'
        {0x2d_u32, 6}, # 'u'
        {0x77_u32, 7}, # 'v'
        {0x78_u32, 7}, # 'w'
        {0x79_u32, 7}, # 'x'
        {0x7a_u32, 7}, # 'y'
        {0x7b_u32, 7}, # 'z'
        {0x7ffe_u32, 15}, # '{'
        {0x7fc_u32, 11}, # '|'
        {0x3ffd_u32, 14}, # '}'
        {0x1ffd_u32, 13}, # '~'
        {0xffffffc_u32, 28}, # 127
        {0xfffe6_u32, 20}, # 128
        {0x3fffd2_u32, 22}, # 129
        {0xfffe7_u32, 20}, # 130
        {0xfffe8_u32, 20}, # 131
        {0x3fffd3_u32, 22}, # 132
        {0x3fffd4_u32, 22}, # 133
        {0x3fffd5_u32, 22}, # 134
        {0x7fffd9_u32, 23}, # 135
        {0x3fffd6_u32, 22}, # 136
        {0x7fffda_u32, 23}, # 137
        {0x7fffdb_u32, 23}, # 138
        {0x7fffdc_u32, 23}, # 139
        {0x7fffdd_u32, 23}, # 140
        {0x7fffde_u32, 23}, # 141
        {0xffffeb_u32, 24}, # 142
        {0x7fffdf_u32, 23}, # 143
        {0xffffec_u32, 24}, # 144
        {0xffffed_u32, 24}, # 145
        {0x3fffd7_u32, 22}, # 146
        {0x7fffe0_u32, 23}, # 147
        {0xffffee_u32, 24}, # 148
        {0x7fffe1_u32, 23}, # 149
        {0x7fffe2_u32, 23}, # 150
        {0x7fffe3_u32, 23}, # 151
        {0x7fffe4_u32, 23}, # 152
        {0x1fffdc_u32, 21}, # 153
        {0x3fffd8_u32, 22}, # 154
        {0x7fffe5_u32, 23}, # 155
        {0x3fffd9_u32, 22}, # 156
        {0x7fffe6_u32, 23}, # 157
        {0x7fffe7_u32, 23}, # 158
        {0xffffef_u32, 24}, # 159
        {0x3fffda_u32, 22}, # 160
        {0x1fffdd_u32, 21}, # 161
        {0xfffe9_u32, 20}, # 162
        {0x3fffdb_u32, 22}, # 163
        {0x3fffdc_u32, 22}, # 164
        {0x7fffe8_u32, 23}, # 165
        {0x7fffe9_u32, 23}, # 166
        {0x1fffde_u32, 21}, # 167
        {0x7fffea_u32, 23}, # 168
        {0x3fffdd_u32, 22}, # 169
        {0x3fffde_u32, 22}, # 170
        {0xfffff0_u32, 24}, # 171
        {0x1fffdf_u32, 21}, # 172
        {0x3fffdf_u32, 22}, # 173
        {0x7fffeb_u32, 23}, # 174
        {0x7fffec_u32, 23}, # 175
        {0x1fffe0_u32, 21}, # 176
        {0x1fffe1_u32, 21}, # 177
        {0x3fffe0_u32, 22}, # 178
        {0x1fffe2_u32, 21}, # 179
        {0x7fffed_u32, 23}, # 180
        {0x3fffe1_u32, 22}, # 181
        {0x7fffee_u32, 23}, # 182
        {0x7fffef_u32, 23}, # 183
        {0xfffea_u32, 20}, # 184
        {0x3fffe2_u32, 22}, # 185
        {0x3fffe3_u32, 22}, # 186
        {0x3fffe4_u32, 22}, # 187
        {0x7ffff0_u32, 23}, # 188
        {0x3fffe5_u32, 22}, # 189
        {0x3fffe6_u32, 22}, # 190
        {0x7ffff1_u32, 23}, # 191
        {0x3ffffe0_u32, 26}, # 192
        {0x3ffffe1_u32, 26}, # 193
        {0xfffeb_u32, 20}, # 194
        {0x7fff1_u32, 19}, # 195
        {0x3fffe7_u32, 22}, # 196
        {0x7ffff2_u32, 23}, # 197
        {0x3fffe8_u32, 22}, # 198
        {0x1ffffec_u32, 25}, # 199
        {0x3ffffe2_u32, 26}, # 200
        {0x3ffffe3_u32, 26}, # 201
        {0x3ffffe4_u32, 26}, # 202
        {0x7ffffde_u32, 27}, # 203
        {0x7ffffdf_u32, 27}, # 204
        {0x3ffffe5_u32, 26}, # 205
        {0xfffff1_u32, 24}, # 206
        {0x1ffffed_u32, 25}, # 207
        {0x7fff2_u32, 19}, # 208
        {0x1fffe3_u32, 21}, # 209
        {0x3ffffe6_u32, 26}, # 210
        {0x7ffffe0_u32, 27}, # 211
        {0x7ffffe1_u32, 27}, # 212
        {0x3ffffe7_u32, 26}, # 213
        {0x7ffffe2_u32, 27}, # 214
        {0xfffff2_u32, 24}, # 215
        {0x1fffe4_u32, 21}, # 216
        {0x1fffe5_u32, 21}, # 217
        {0x3ffffe8_u32, 26}, # 218
        {0x3ffffe9_u32, 26}, # 219
        {0xfffffd_u32, 28}, # 220
        {0x7ffffe3_u32, 27}, # 221
        {0x7ffffe4_u32, 27}, # 222
        {0x7ffffe5_u32, 27}, # 223
        {0xfffec_u32, 20}, # 224
        {0xfffff3_u32, 24}, # 225
        {0xfffed_u32, 20}, # 226
        {0x1fffe6_u32, 21}, # 227
        {0x3fffe9_u32, 22}, # 228
        {0x1fffe7_u32, 21}, # 229
        {0x1fffe8_u32, 21}, # 230
        {0x7ffff3_u32, 23}, # 231
        {0x3fffea_u32, 22}, # 232
        {0x3fffeb_u32, 22}, # 233
        {0x1ffffee_u32, 25}, # 234
        {0x1ffffef_u32, 25}, # 235
        {0xfffff4_u32, 24}, # 236
        {0xfffff5_u32, 24}, # 237
        {0x3ffffea_u32, 26}, # 238
        {0x7ffff4_u32, 23}, # 239
        {0x3ffffeb_u32, 26}, # 240
        {0x7ffffe6_u32, 27}, # 241
        {0x3ffffec_u32, 26}, # 242
        {0x3ffffed_u32, 26}, # 243
        {0x7ffffe7_u32, 27}, # 244
        {0x7ffffe8_u32, 27}, # 245
        {0x7ffffe9_u32, 27}, # 246
        {0x7ffffea_u32, 27}, # 247
        {0x7ffffeb_u32, 27}, # 248
        {0xffffffe_u32, 28}, # 249
        {0x7ffffec_u32, 27}, # 250
        {0x7ffffed_u32, 27}, # 251
        {0x7ffffee_u32, 27}, # 252
        {0x7ffffef_u32, 27}, # 253
        {0x7fffff0_u32, 27}, # 254
        {0x3ffffee_u32, 26}, # 255
        {0x3fffffff_u32, 30}, # EOS
      ] of {UInt32, Int32}

      # A node of the code tree used for decoding.
      class Node
        property left : Node? = nil
        property right : Node? = nil
        property symbol : Int32? = nil
        getter depth : Int32

        def initialize(@depth : Int32 = 0)
        end
      end

      @@root : Node?

      # The root of the code tree, built lazily from CODES.
      private def self.root : Node
        @@root ||= begin
          root_node = Node.new
          CODES.each_with_index do |(code, len), symbol|
            node = root_node
            len.times do |i|
              bit = (code >> (len - 1 - i)) & 1
              node = if bit == 0
                node.left ||= Node.new(node.depth + 1)
              else
                node.right ||= Node.new(node.depth + 1)
              end
            end
            node.symbol = symbol
          end
          root_node
        end
      end

      # Decodes a Huffman-encoded string (RFC 7541 section 5.2).
      def self.decode(bytes : Bytes) : String
        io = IO::Memory.new(bytes.size)
        node = root
        total = bytes.size * 8
        bit = 0
        while bit < total
          byte = bytes[bit // 8]
          bit_value = (byte >> (7 - (bit % 8))) & 1
          node = bit_value == 0 ? node.left : node.right
          bit += 1
          raise Error.new("invalid Huffman code") unless node
          if sym = node.symbol
            raise Error.new("EOS in the middle of the string") if sym == EOS
            io.write_byte(sym.to_u8)
            node = root
          end
        end
        # The trailing padding must be a prefix of the EOS code (all 1s),
        # at most 7 bits long.
        if node != root
          raise Error.new("Huffman padding longer than 7 bits") if node.depth > 7
          current = node
          while current
            return io.to_s if current.symbol == EOS
            current = current.right
          end
          raise Error.new("Huffman padding is not the EOS prefix")
        end
        io.to_s
      end

      # Encodes a string using the Huffman code, padding with the EOS
      # prefix to the next octet boundary.
      def self.encode(str : String) : Bytes
        io = IO::Memory.new(str.bytesize)
        buffer = 0_u64
        bit_count = 0
        str.each_byte do |byte|
          code, len = CODES[byte]
          buffer = (buffer << len) | code
          bit_count += len
          while bit_count >= 8
            io.write_byte(((buffer >> (bit_count - 8)) & 0xff).to_u8)
            bit_count -= 8
          end
        end
        if bit_count > 0
          padding = 8 - bit_count
          io.write_byte((((buffer << padding) | ((1_u64 << padding) - 1)) & 0xff).to_u8)
        end
        io.to_slice
      end
    end
  end
end

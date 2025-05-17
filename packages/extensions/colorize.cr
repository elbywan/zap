{% if flag?("preview_mt") %}
{% verbatim do %}
require "colorize"
require "concurrency/mutex"

# The original Colorize module is not thread safe, so we need to wrap it in a thread safe version.
# I could not find a way to do this without copy pasting the entire module, so here it is.
struct Colorize::Object::Sync(T)
  @@mutex = Concurrency::Mutex.new

  # Surrounds *io* by the ANSI escape codes and lets you build colored strings:
  #
  # ```
  # require "colorize"
  #
  # io = IO::Memory.new
  #
  # Colorize.with.red.surround(io) do
  #   io << "colorful"
  #   Colorize.with.green.bold.surround(io) do
  #     io << " hello "
  #   end
  #   Colorize.with.blue.surround(io) do
  #     io << "world"
  #   end
  #   io << " string"
  # end
  #
  # io.to_s # returns a colorful string where "colorful" is red, "hello" green, "world" blue and " string" red again
  # ```
  def surround(io = STDOUT)
    return yield io unless @enabled

    Object::Sync.surround(io, to_named_tuple) do |io|
      yield io
    end
  end

  ###### The rest is copy pasta from crystal/src/colorize.cr

  private COLORS = %w(default black red green yellow blue magenta cyan light_gray dark_gray light_red light_green light_yellow light_blue light_magenta light_cyan white)

  @fore : Color
  @back : Color

  def initialize(@object : T)
    @fore = ColorANSI::Default
    @back = ColorANSI::Default
    @mode = Mode::None
    @enabled = Colorize.enabled?
  end

  {% for name in COLORS %}
    def {{name.id}}
      @fore = ColorANSI::{{name.camelcase.id}}
      self
    end

    def on_{{name.id}}
      @back = ColorANSI::{{name.camelcase.id}}
      self
    end
  {% end %}

  {% for mode in Mode.constants.reject { |constant| constant == "All" || constant == "None" } %}
    # Apply text decoration `Mode::{{ mode }}`.
    def {{mode.underscore.id}}
      mode Mode::{{mode.id}}
    end
  {% end %}

  def fore(color : Symbol) : self
    {% for name in COLORS %}
      if color == :{{name.id}}
        @fore = ColorANSI::{{name.camelcase.id}}
        return self
      end
    {% end %}

    raise ArgumentError.new "Unknown color: #{color}"
  end

  def fore(@fore : Color) : self
    self
  end

  def fore(fore : UInt8)
    @fore = Color256.new(fore)
    self
  end

  def fore(r : UInt8, g : UInt8, b : UInt8)
    @fore = ColorRGB.new(r, g, b)
    self
  end

  def back(color : Symbol) : self
    {% for name in COLORS %}
      if color == :{{name.id}}
        @back = ColorANSI::{{name.camelcase.id}}
        return self
      end
    {% end %}

    raise ArgumentError.new "Unknown color: #{color}"
  end

  def back(@back : Color) : self
    self
  end

  def back(back : UInt8)
    @back = Color256.new(back)
    self
  end

  def back(r : UInt8, g : UInt8, b : UInt8)
    @back = ColorRGB.new(r, g, b)
    self
  end

  # Adds *mode* to the text's decorations.
  def mode(mode : Mode) : self
    @mode |= mode
    self
  end

  def on(color : Symbol)
    back color
  end

  # Enables or disables colors and text decoration on this object.
  def toggle(flag)
    @enabled = !!flag
    self
  end

  # Appends this object colored and with text decoration to *io*.
  def to_s(io : IO) : Nil
    surround(io) do
      io << @object
    end
  end

  # Inspects this object and makes the ANSI escape codes visible.
  def inspect(io : IO) : Nil
    surround(io) do
      @object.inspect(io)
    end
  end

  private def to_named_tuple
    {
      fore: @fore,
      back: @back,
      mode: @mode,
    }
  end

  @@last_color = {
    fore: ColorANSI::Default.as(Color),
    back: ColorANSI::Default.as(Color),
    mode: Mode::None,
  }

  protected def self.surround(io, color)
    @@mutex.synchronize do
      last_color = @@last_color
      must_append_end = append_start(io, color)
      @@last_color = color

      begin
        yield io
      ensure
        append_start(io, last_color) if must_append_end
        @@last_color = last_color
      end
    end
  end

  private def self.append_start(io, color)
    last_color_is_default =
      @@last_color[:fore] == ColorANSI::Default &&
        @@last_color[:back] == ColorANSI::Default &&
        @@last_color[:mode].none?

    fore = color[:fore]
    back = color[:back]
    mode = color[:mode]

    fore_is_default = fore == ColorANSI::Default
    back_is_default = back == ColorANSI::Default

    if fore_is_default && back_is_default && mode.none? && last_color_is_default || @@last_color == color
      false
    else
      io << "\e["

      printed = false

      unless last_color_is_default
        io << '0'
        printed = true
      end

      unless fore_is_default
        io << ';' if printed
        fore.fore io
        printed = true
      end

      unless back_is_default
        io << ';' if printed
        back.back io
        printed = true
      end

      each_code(mode) do |code|
        io << ';' if printed
        io << code
        printed = true
      end

      io << 'm'

      true
    end
  end
end

private def each_code(mode : Colorize::Mode)
  yield '1' if mode.bold?
  yield '2' if mode.dim?
  yield '4' if mode.underline?
  yield '5' if mode.blink?
  yield '7' if mode.reverse?
  yield '8' if mode.hidden?
end

module Colorize::ObjectExtensions::Sync
  # Turns `self` into a `Colorize::Object`.
  def colorize : Colorize::Object::Sync
    Colorize::Object::Sync.new(self)
  end

  # Wraps `self` in a `Colorize::Object` and colors it with the given `Color256`
  # made up from the single *fore* byte.
  def colorize(fore : UInt8)
    Colorize::Object::Sync.new(self).fore(fore)
  end

  # Wraps `self` in a `Colorize::Object` and colors it with the given `Color256` made
  # up from the given *r*ed, *g*reen and *b*lue values.
  def colorize(r : UInt8, g : UInt8, b : UInt8)
    Colorize::Object::Sync.new(self).fore(r, g, b)
  end

  # Wraps `self` in a `Colorize::Object` and colors it with the given *fore* `Color`.
  def colorize(fore : Color)
    Colorize::Object::Sync.new(self).fore(fore)
  end

  # Wraps `self` in a `Colorize::Object` and colors it with the given *fore* color.
  def colorize(fore : Symbol)
    Colorize::Object::Sync.new(self).fore(fore)
  end
end

class Object
  include Colorize::ObjectExtensions::Sync
end

{% end %}
{% end %}

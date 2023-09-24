require "ini"

struct Zap::Npmrc
  getter registry : String = "https://registry.npmjs.org/"
  getter scoped_registries : Hash(String, String) = {} of String => String
  getter registries_auth : Hash(String, RegistryAuth) = {} of String => RegistryAuth
  getter cafile : String? = nil
  getter capath : String? = nil
  getter strict_ssl : Bool = true

  record RegistryAuth,
    auth : String? = nil,
    authToken : String? = nil,
    certfile : String? = nil,
    keyfile : String? = nil

  def initialize(project_path : Path | String)
    ini = [
      ::File.expand_path("/etc/npmrc"),
      ::File.expand_path("~/.npmrc", home: true),
      Path.new(project_path) / ".npmrc",
    ].reduce(nil) do |acc, path|
      if File.exists?(path)
        ini_data = INI.parse(File.read(path))
        if acc.nil?
          ini_data[""]?
        else
          ini_data[""]?.try { |h| acc.merge(h) }
        end
      else
        acc
      end
    end

    ini.try &.each { |(k, v)| init(k, v) }
  end

  protected def init(key : String, value : String)
    key, scope = self.class.scoped_key?(key)
    value = self.class.parse_value(value)

    case key
    when "registry"
      if scope.nil?
        @registry = value
      else
        @scoped_registries[scope] = value
      end
    when "cafile"
      @cafile = value
    when "capath"
      @capath = value
    when "strict-ssl"
      @strict_ssl = value !~ /^false$/i && value != "0"
    when "_auth"
      unless scope.nil?
        get_registry_keys(scope).each { |key|
          @registries_auth[key] ||= RegistryAuth.new
          @registries_auth[key] = @registries_auth[key].copy_with(auth: value)
        }
      end
    when "_authToken"
      unless scope.nil?
        get_registry_keys(scope).each { |key|
          @registries_auth[key] ||= RegistryAuth.new
          @registries_auth[key] = @registries_auth[key].copy_with(authToken: value)
        }
      end
    when "certfile"
      unless scope.nil?
        get_registry_keys(scope).each { |key|
          @registries_auth[key] ||= RegistryAuth.new
          @registries_auth[key] = @registries_auth[key].copy_with(certfile: value)
        }
      end
    when "keyfile"
      unless scope.nil?
        get_registry_keys(scope).each { |key|
          @registries_auth[key] ||= RegistryAuth.new
          @registries_auth[key] = @registries_auth[key].copy_with(keyfile: value)
        }
      end
    end
  end

  protected def get_registry_keys(scope : String)
    ([] of String).tap do |array|
      uri = URI.parse(scope)
      if uri.scheme
        array << uri.to_s
      else
        uri.scheme = "http"
        array << uri.to_s
        uri.scheme = "https"
        array << uri.to_s
      end
    end
  end

  protected def self.scoped_key?(key : String)
    k = key.split(':')
    k.size >= 2 ? {k.last, k[...-1].join(':')} : {key, nil}
  end

  protected def self.parse_value(value : String)
    String.build do |str|
      previous_char = nil
      parsing_env_var = false
      env_var = String::Builder.new

      value.each_char do |char|
        if parsing_env_var
          if char == '}'
            str << ENV[env_var.to_s]? || ""
            parsing_env_var = false
            env_var = String::Builder.new
          else
            env_var << char
          end
        elsif char == '{' && previous_char == '$'
          parsing_env_var = true
        else
          str << char
        end
        previous_char = char
      end
    end
  end
end

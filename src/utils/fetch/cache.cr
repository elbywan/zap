class Zap::Utils::Fetch
  abstract class Cache
    abstract def get(url : String, etag : String?) : String?
    abstract def set(url : String, value : String, expiry : Time::Span?, etag : String?) : Nil

    def self.hash(name)
      Digest::SHA1.hexdigest(name)
    end

    class InMemory < Cache
      def initialize(@fallback : Cache? = nil)
        @cache = SafeHash(String, String).new
      end

      def get(url : String, etag : String? = nil, *, fallback = true) : String?
        key = self.class.hash(url)
        own = @cache[key]?
        return own if own
        if fallback
          fb = @fallback.try &.get(key, etag)
          @cache[key] = fb if fb
          fb
        end
      rescue
        # cache miss
      end

      def set(url : String, value : String, expiry : Time::Span? = nil, etag : String? = nil, *, fallback = true) : Nil
        key = self.class.hash(url)
        @cache[key] = value
        @fallback.try &.set(key, value, expiry, etag) if fallback
        value
      rescue
        # miss
      end
    end

    class InStore < Cache
      BODY_FILE_NAME      = "body"
      BODY_FILE_NAME_TEMP = "body.temp"
      META_FILE_NAME      = "meta.json"
      META_FILE_NAME_TEMP = "meta.json.temp"
      @path : Path
      @bypass_staleness_checks : Bool
      @raise_on_cache_miss : Bool

      def initialize(store_path, *, @bypass_staleness_checks : Bool = false, @raise_on_cache_miss : Bool = false)
        @path = Path.new(store_path, CACHE_DIR)
        Utils::Directories.mkdir_p(@path)
      end

      def get(url : String, etag : String? = nil) : String?
        key = self.class.hash(url)
        path = @path / key / BODY_FILE_NAME
        return nil unless ::File.readable?(path)
        return ::File.read(path) if @bypass_staleness_checks
        meta_path = @path / key / META_FILE_NAME
        meta = ::File.read(meta_path) if ::File.readable?(meta_path)
        meta = JSON.parse(meta) if meta
        meta_etag = meta.try &.["etag"]?.try &.as_s?
        if expiry = meta.try &.["expiry"]?.try &.as_i64?
          if expiry > Time.utc.to_unix
            Log.debug { "(#{url}) Cache hit - serving metadata from #{path}" }
            return ::File.read(path)
          end
        end
        if etag && meta_etag && meta_etag == etag
          Log.debug { "(#{url}) Cache hit (etag) - serving metadata from #{path}" }
          return ::File.read(path)
        end
      end

      def set(url : String, value : String, expiry : Time::Span? = nil, etag : String? = nil) : Nil
        key = self.class.hash(url)
        root_path = @path / key
        body_file_path = root_path / BODY_FILE_NAME
        body_file_path_temp = root_path / BODY_FILE_NAME_TEMP
        meta_file_path = root_path / META_FILE_NAME
        meta_file_path_temp = root_path / META_FILE_NAME_TEMP
        Log.debug { "(#{url}) Storing metadata at #{root_path}" }
        Utils::Directories.mkdir_p(root_path)
        ::File.write(body_file_path_temp, value)
        ::File.rename(body_file_path_temp, body_file_path)
        ::File.write(meta_file_path_temp, {"etag": etag, expiry: expiry ? (Time.utc + expiry).to_unix : nil}.to_json)
        ::File.rename(meta_file_path_temp, meta_file_path)
      end
    end
  end
end

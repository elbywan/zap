require "msgpack"
require "utils/directories"
require "utils/misc"
require "concurrency/data_structures/safe_hash"

class Fetch(T)
  abstract class Cache(T)
    Log = ::Log.for("zap.fetch.cache")

    abstract def get(key_str : String, etag : String?) : T?
    abstract def get(key_str : String, &etag : -> String?) : T?
    abstract def set(key_str : String, value : T, expiry : Time::Span?, etag : String?) : Nil

    def self.hash(str)
      Digest::SHA1.hexdigest(str)
    end

    class InMemory(T) < Cache(T)
      def initialize(@fallback : Cache(T)? = nil)
        @cache = Concurrency::SafeHash(String, T).new
      end

      def get(key_str : String, etag : String? = nil, *, fallback = true) : T?
        key = self.class.hash(key_str)
        own = @cache[key]?
        return own if own
        if fallback
          fb = @fallback.try &.get(key, etag)
          @cache[key] = fb if fb
          fb
        end
      rescue ex
        Log.debug { "(#{key_str}) In-memory cache miss: #{ex.message}" }
        nil
      end

      def get(key_str : String, *, fallback = true, &etag : -> String?) : T?
        key = self.class.hash(key_str)
        own = @cache[key]?
        return own if own
        if fallback
          fb = @fallback.try &.get(key, &etag)
          @cache[key] = fb if fb
          fb
        end
      rescue ex
        Log.debug { "(#{key_str}) In-memory cache miss: #{ex.message}" }
        nil
      end

      def set(key_str : String, value : T, expiry : Time::Span? = nil, etag : String? = nil, *, fallback = true) : Nil
        key = self.class.hash(key_str)
        @cache[key] = value
        @fallback.try &.set(key, value, expiry, etag) if fallback
        value
      rescue ex
        Log.debug { "(#{key_str}) Failed to set in-memory cache: #{ex.message}" }
        nil
      end
    end

    class InStore(T) < Cache(T)
      BODY_FILE_NAME      = "body"
      BODY_FILE_NAME_TEMP = "body.temp"
      META_FILE_NAME      = "meta"
      META_FILE_NAME_TEMP = "meta.temp"
      @path : Path
      @bypass_staleness_checks : Bool
      @raise_on_cache_miss : Bool

      abstract struct Serializer(T)
        abstract def serialize(value : T) : Bytes | String | IO
        abstract def deserialize(value : IO) : T
      end

      struct NoopSerializer < Serializer(String)
        def serialize(value : String) : Bytes | String | IO
          value
        end

        def deserialize(value : IO) : String
          value.gets_to_end
        end
      end

      struct MessagePackSerializer(T) < Cache::InStore::Serializer(T)
        def serialize(value : T) : Bytes | String | IO
          value.to_msgpack
        end

        def deserialize(value : IO) : T
          T.from_msgpack(value)
        end
      end

      private struct Metadata
        include MessagePack::Serializable

        getter etag : String?
        getter expiry : Int64?

        def initialize(@etag : String? = nil, @expiry : Int64? = nil); end
      end

      def initialize(
        store_path,
        *,
        @serializer : Serializer(T),
        @bypass_staleness_checks : Bool = false,
        @raise_on_cache_miss : Bool = false,
      )
        @path = Path.new(store_path, CACHE_DIR)
        Utils::Directories.mkdir_p(@path)
      end

      def get(key_str : String, etag : String? = nil) : T?
        key = self.class.hash(key_str)
        path = @path / key / BODY_FILE_NAME
        Utils::Misc.block {
          next nil unless ::File.readable?(path)
          next path if @bypass_staleness_checks
          meta_path = @path / key / META_FILE_NAME

          meta = begin
            ::File.open(meta_path) { |io| Metadata.from_msgpack(io) }
          rescue
            nil
          end

          if expiry = meta.try(&.expiry)
            if expiry > Time.utc.to_unix
              Log.debug { "(#{key_str}) Cache hit - serving metadata from #{path}" }
              next path
            end
          end

          meta_etag = meta.try(&.etag)
          if etag && meta_etag && meta_etag == etag
            Log.debug { "(#{key_str}) Cache hit (etag) - serving metadata from #{path}" }
            next path
          end
        }.try do |path|
          io = ::File.open(path)
          @serializer.deserialize(io)
        ensure
          io.try &.close
        end
      end

      def get(key_str : String, &get_etag : -> String?) : T?
        key = self.class.hash(key_str)
        path = @path / key / BODY_FILE_NAME
        Utils::Misc.block {
          next nil unless ::File.readable?(path)
          next path if @bypass_staleness_checks
          meta_path = @path / key / META_FILE_NAME

          meta = begin
            ::File.open(meta_path) { |io| Metadata.from_msgpack(io) }
          rescue
            nil
          end

          if expiry = meta.try(&.expiry)
            if expiry > Time.utc.to_unix
              Log.debug { "(#{key_str}) Cache hit - serving metadata from #{path}" }
              next path
            end
          end

          if meta_etag = meta.try(&.etag)
            etag = get_etag.call
            if etag && meta_etag == etag
              Log.debug { "(#{key_str}) Cache hit (etag) - serving metadata from #{path}" }
              next path
            end
          end
        }.try do |path|
          io = ::File.open(path)
          @serializer.deserialize(io)
        ensure
          io.try &.close
        end
      end

      def set(key_str : String, value : T, expiry : Time::Span? = nil, etag : String? = nil) : Nil
        key = self.class.hash(key_str)
        root_path = @path / key
        body_file_path = root_path / BODY_FILE_NAME
        body_file_path_temp = root_path / BODY_FILE_NAME_TEMP
        meta_file_path = root_path / META_FILE_NAME
        meta_file_path_temp = root_path / META_FILE_NAME_TEMP
        Log.debug { "(#{key_str}) Storing metadata at #{root_path}" }
        Utils::Directories.mkdir_p(root_path)
        ::File.write(body_file_path_temp, @serializer.serialize(value))
        ::File.rename(body_file_path_temp, body_file_path)
        metadata = Metadata.new(etag, expiry ? (Time.utc + expiry).to_unix : nil)
        ::File.write(meta_file_path_temp, metadata.to_msgpack)
        ::File.rename(meta_file_path_temp, meta_file_path)
      end
    end
  end
end

struct Store
  STORE_PATH = ENV["ZAP_STORE_PATH"]? ||
               {% if flag?(:windows) %}
                 File.expand_path("%LocalAppData%/.zap/store", home: true)
               {% else %}
                 File.expand_path("~/.zap/store", home: true)
               {% end %}
  getter store_path : Path

  def initialize(config : Hash(String, String) = {} of String => String)
    @store_path = Path.new(config[:store_path]? || STORE_PATH)
    Dir.mkdir_p(store_path) unless Dir.exists?(store_path)
  end

  def package_exists?(name : String, version : String)
    Dir.exists?(store_path / "#{name}@#{version}")
  end

  def init_package(name : String, version : String)
    path = store_path / "#{name}@#{version}"
    Dir.mkdir_p(path)
  end

  def remove_package(name : String, version : String)
    Dir.delete(store_path / "#{name}@#{version}")
  end

  def store_package_file(package_name : String, package_version : String, relative_file_path : String | Path, file_io : IO)
    file_path = store_path / "#{package_name}@#{package_version}" / relative_file_path
    Dir.mkdir_p(file_path.dirname)
    File.open(file_path, "w") do |file|
      IO.copy file_io, file
    end
  end

  def store_package_dir(package_name : String, package_version : String, relative_dir_path : String | Path)
    file_path = store_path / "#{package_name}@#{package_version}" / relative_dir_path
    Dir.mkdir_p(file_path)
  end

  def package(name : String, version : String)
    Package.init(store_path / "#{name}@#{version}")
  end
end

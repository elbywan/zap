require "json"
require "yaml"
require "msgpack"
require "concurrency/data_structures/safe_array"

class Data::Package
  module DependenciesReferences
    @[JSON::Field(ignore: true)]
    @[YAML::Field(ignore: true)]
    @[MessagePack::Field(ignore: true)]
    getter dependencies_refs = Concurrency::SafeArray(Package).new
    @[JSON::Field(ignore: true)]
    @[YAML::Field(ignore: true)]
    @[MessagePack::Field(ignore: true)]
    getter dev_dependencies_refs = Concurrency::SafeArray(Package).new
    @[JSON::Field(ignore: true)]
    @[YAML::Field(ignore: true)]
    @[MessagePack::Field(ignore: true)]
    getter optional_dependencies_refs = Concurrency::SafeArray(Package).new

    def each_dependency_hash(*,
                             include_dev : Bool = true,
                             include_optional : Bool = true,
                             &block : (Hash(String, String | Alias)?, DependencyType) -> T) forall T
      block.call(dependencies, DependencyType::Dependency)
      block.call(dev_dependencies, DependencyType::DevDependency) if include_dev
      block.call(optional_dependencies, DependencyType::OptionalDependency) if include_optional
    end

    def each_dependency(*,
                        include_dev : Bool = true,
                        include_optional : Bool = true,
                        &block : (String, String | Alias, DependencyType) -> Nil)
      each_dependency_hash(include_dev: include_dev, include_optional: include_optional) do |deps, type|
        deps.try &.each { |dep, version| block.call(dep, version, type) }
      end
    end

    def each_dependency_ref(*,
                            include_dev : Bool = true,
                            include_optional : Bool = true,
                            &block : (Package, DependencyType) -> Nil)
      dependencies_refs.each do |package|
        block.call(package, DependencyType::Dependency)
      end
      if include_dev
        dev_dependencies_refs.each do |package|
          block.call(package, DependencyType::DevDependency)
        end
      end
      if include_optional
        optional_dependencies_refs.each do |package|
          block.call(package, DependencyType::OptionalDependency)
        end
      end
    end

    def map_dependencies(*,
                         include_dev : Bool = true,
                         include_optional : Bool = true,
                         &block : (String, String | Alias, DependencyType) -> T) : Array(T) forall T
      mapped_array = Array(T).new(
        dependencies_size(include_dev: include_dev, include_optional: include_optional)
      )
      each_dependency(include_dev: include_dev, include_optional: include_optional) do |dep, version, type|
        mapped_array << block.call(dep, version, type)
      end
      mapped_array
    end

    def dependencies_size(*, include_dev : Bool = true, include_optional : Bool = true) : Int
      dependencies.try(&.size) || 0 +
        (include_dev ? dev_dependencies.try(&.size) || 0 : 0) +
        (include_optional ? optional_dependencies.try(&.size) || 0 : 0)
    end

    def dependency_specifier?(name : String, *, include_dev : Bool = true, include_optional : Bool = true) : (String | Package::Alias)?
      dependencies.try &.[name]? ||
        (include_dev ? dev_dependencies.try(&.[name]?) : nil) ||
        (include_optional ? optional_dependencies.try(&.[name]?) : nil)
    end

    def has_dependency?(name : String, *, include_dev : Bool = true, include_optional : Bool = true) : Bool?
      dependencies.try(&.has_key?(name)) ||
        (include_dev ? dev_dependencies.try(&.has_key?(name)) : false) ||
        (include_optional ? optional_dependencies.try(&.has_key?(name)) : false)
    end

    def dependency_specifier(name : String, specifier : (String | Package::Alias), type : DependencyType? = nil) : Nil
      if type
        case type
        when .dependency?
          if (dependencies = @dependencies) && dependencies.has_key?(name)
            dependencies[name] = specifier
          end
        when .dev_dependency?
          if (dev_dependencies = @dev_dependencies) && dev_dependencies.has_key?(name)
            dev_dependencies[name] = specifier
          end
        when .optional_dependency?
          if (optional_dependencies = @optional_dependencies) && optional_dependencies.has_key?(name)
            optional_dependencies[name] = specifier
          end
        end
      else
        if (dependencies = @dependencies) && dependencies.has_key?(name)
          dependencies[name] = specifier
        end

        if (dev_dependencies = @dev_dependencies) && dev_dependencies.has_key?(name)
          dev_dependencies[name] = specifier
        end

        if (optional_dependencies = @optional_dependencies) && optional_dependencies.has_key?(name)
          optional_dependencies[name] = specifier
        end
      end
    end

    def trim_dependencies_fields
      if (dependencies = @dependencies) && dependencies.empty?
        @dependencies = nil
      end
      if (dev_dependencies = @dev_dependencies) && dev_dependencies.empty?
        @dev_dependencies = nil
      end
      if (optional_dependencies = @optional_dependencies) && optional_dependencies.empty?
        @optional_dependencies = nil
      end
      if (peer_dependencies = @peer_dependencies) && peer_dependencies.empty?
        @peer_dependencies = nil
      end
    end

    def add_dependency_ref(package : Data::Package, type : DependencyType? = nil)
      case type
      when .dependency?, .nil?
        dependencies_refs << package
      when .dev_dependency?
        dev_dependencies_refs << package
      when .optional_dependency?
        optional_dependencies_refs << package
      end
    end
  end
end

module Zap::Commands::Why
  alias PackageResult = {root: Lockfile::Root, ancestors: Deque({Package, DependencyType}), type: DependencyType}

  DEPENDS_ON_CHAR               = '←'
  ANCESTOR_PATH_PREFIX_CHAR     = '├'
  ANCESTOR_PATH_END_PREFIX_CHAR = '└'

  def self.run(config : Config, why_config : Config::Why)
    why_config = why_config.from_args(ARGV)
    Log.debug { "Parsed package arguments: #{why_config.packages}" }

    # Infer context like the nearest package.json file and workspaces
    inferred_context = config.infer_context
    workspaces, config = inferred_context.workspaces, inferred_context.config
    lockfile = Lockfile.new(config.prefix)

    Log.debug { "Lockfile read status: #{lockfile.read_status}" }

    results = Hash(Package, Array(PackageResult)).new

    # filter the roots in case the user provided a filter
    roots = lockfile.filter_roots(inferred_context.main_package, inferred_context.get_scope(:command))

    lockfile.crawl(roots: roots) do |dependency, type, root, ancestors|
      # for each package in the lockfile, check if it matches the provided pattern
      next unless why_config.packages.any? { |name_pattern, version|
                    name_pattern =~ dependency.name && (!version || version.satisfies?(dependency.version))
                  }
      result = results[dependency] ||= [] of PackageResult
      # add to the results the path from the root to the package
      result << {
        root:      root,
        ancestors: ancestors.dup,
        type:      type,
      }
    end

    # for each package matching the pattern, get the results and format them
    output_by_package = results.map do |package, results|
      output = String.build do |str|
        str << "#{package.key}".colorize.yellow.bold.underline << NEW_LINE
        str << NEW_LINE
        results
          .group_by { |result| result[:root] }
          .each do |root, root_results|
            str << format_root_results(root, root_results, config: why_config)
            str << NEW_LINE
          end
      end
      {package.key, output}
    end

    # sort the final ouput by package key
    output_by_package.sort { |(key1, _), (key2, _)| key1 <=> key2 }.each do |_, output|
      puts output
    end
  end

  private def self.format_root_results(root, root_results, *, config : Config::Why)
    String.build do |str|
      str << root_results
        .sort(&->sort_by_direct_ancestor(PackageResult, PackageResult))
        .group_by(&->group_by_direct_ancestor(PackageResult))
        .map { |ancestor, results| direct_ancestor_output(ancestor, results, config: config) }
        .join(NEW_LINE)
      str << NEW_LINE
    end
  end

  private def self.sort_by_direct_ancestor(result1 : PackageResult, result2 : PackageResult)
    # Display the root package first
    return -1 if result1[:ancestors].size == 0
    return 1 if result2[:ancestors].size == 0
    # Sort by the direct ancestor key in ascending order
    ancestor_diff = result1[:ancestors].last[0].key <=> result2[:ancestors].last[0].key
    if ancestor_diff == 0
      result1[:ancestors].size - result2[:ancestors].size
    else
      ancestor_diff
    end
  end

  private def self.group_by_direct_ancestor(result : PackageResult)
    if result[:ancestors].size == 0
      "#{result[:root].name}@#{result[:root].version}"
    else
      result[:ancestors].last[0].key
    end
  end

  private def self.direct_ancestor_output(direct_ancestor : String, direct_ancestor_results : Array(PackageResult), *, config : Config::Why)
    String.build do |result_str|
      direct_ancestor_name, direct_ancestor_version = Utils::Various.parse_key(direct_ancestor)
      result_str << "#{direct_ancestor_name.colorize.bold.cyan}#{"@#{direct_ancestor_version}"}"
      unless config.short
        result_str << NEW_LINE
        result_str << direct_ancestor_results.map_with_index { |result, index|
          ancestor_path_output(result, last_ancestor: index == direct_ancestor_results.size - 1)
        }.join(NEW_LINE)
      end
    end
  end

  private def self.ancestor_path_output(result : PackageResult, *, last_ancestor : Bool = false)
    root = result[:root]

    ancestors_str = result[:ancestors].reverse!.map_with_index { |(ancestor, type), index|
      name, version = Utils::Various.parse_key(ancestor.key)
      "#{name.colorize.dim}#{"@#{version}".colorize.dim}#{type.dependency? ? "" : " (#{type.to_s.camelcase(lower: true)})".colorize.dim}"
    }.join(" #{DEPENDS_ON_CHAR} ")

    prefix = last_ancestor ? ANCESTOR_PATH_END_PREFIX_CHAR : ANCESTOR_PATH_PREFIX_CHAR

    if ancestors_str.empty?
      "    #{prefix.colorize.cyan.bold.dim} #{root.name.colorize.magenta.bold}#{"@#{root.version}".colorize.dim} #{"(#{result[:type].to_s.camelcase(lower: true)})".colorize.dim}"
    else
      "    #{prefix.colorize.cyan.bold.dim} #{ancestors_str} #{DEPENDS_ON_CHAR} #{"#{root.name}@#{root.version}".colorize.magenta}"
    end
  end
end

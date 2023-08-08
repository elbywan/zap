module Zap::Commands::Why
  alias PackageResult = {root: Lockfile::Root, ancestors: Deque({Package, DependencyType}), type: DependencyType}

  LEFT_ARROW_CHAR = '←'

  def self.run(config : Config, why_config : Config::Why)
    why_config = why_config.from_args(ARGV)
    Log.debug { "Parsed package arguments: #{why_config.packages}" }

    # Infer context like the nearest package.json file and workspaces
    inferred_context = config.infer_context
    workspaces, config = inferred_context.workspaces, inferred_context.config
    lockfile = Lockfile.new(config.prefix)

    Log.debug { "Lockfile read status: #{lockfile.read_status}" }

    results = Hash(Package, Array(PackageResult)).new

    lockfile.crawl do |dependency, type, root, ancestors|
      next unless why_config.packages.any? { |name_pattern, version|
                    name_pattern =~ dependency.name && (!version || version.satisfies?(dependency.version))
                  }
      result = results[dependency] ||= [] of PackageResult
      result << {
        root:      root,
        ancestors: ancestors.dup,
        type:      type,
      }
    end

    output_by_package = results.map do |package, result|
      output = String.build do |str|
        str << "#{package.key}".colorize.yellow.bold.underline << "\n"
        str << "\n"
        results_by_root = result.group_by { |result| result[:root] }
        results_by_root.each do |root, results|
          str << results.sort { |result1, result2|
            # Display the root package first
            next -1 if result1[:ancestors].size == 0
            next 1 if result2[:ancestors].size == 0
            # Sort by the direct ancestor key in ascending order
            ancestor_diff = result1[:ancestors].last[0].key <=> result2[:ancestors].last[0].key
            if ancestor_diff == 0
              result1[:ancestors].size - result2[:ancestors].size
            else
              ancestor_diff
            end
          }.map { |result|
            ancestors_str = result[:ancestors].reverse!.map_with_index { |(ancestor, type), index|
              name, version = Utils::Various.parse_key(ancestor.key)
              "#{index == 0 ? name.colorize.bold.cyan : name.colorize.dim}#{index == 0 ? "@#{version}" : "@#{version}".colorize.dim}#{type.dependency? ? "" : " (#{type.to_s.camelcase(lower: true)})".colorize.dim}"
            }.join(" #{LEFT_ARROW_CHAR} ")

            if ancestors_str.empty?
              "#{root.name.colorize.magenta.bold}#{"@#{root.version}".colorize.dim} #{"(#{result[:type].to_s.camelcase(lower: true)})".colorize.dim}"
            else
              "#{ancestors_str} #{LEFT_ARROW_CHAR} #{"#{root.name}@#{root.version}".colorize.magenta}"
            end
          }.join('\n') << "\n"
          str << "\n"
        end
      end
      { package.key, output }
    end

    output_by_package.sort { |(key1, _), (key2, _)| key1 <=> key2 }.each do |_, output|
      puts output
    end
  end
end

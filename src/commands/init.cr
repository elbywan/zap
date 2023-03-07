module Zap::Commands::Init
  macro prompt(description, field_name)
    unless init_config.yes
      print "#{ {{ description }} }: (#{ {{ field_name }} }) "
      %reply = gets
      {{ field_name.id }} = !%reply || %reply.empty? ? {{ field_name.id }} : %reply.strip
    end
  end

  def self.read_field(pkg, *field_names)
    pkg.try(&.dig?(*field_names)).try(&.as_s?)
  end

  def self.run(
    config : Config,
    init_config : Config::Init
  )
    prefix_path = Path.new(config.prefix)
    package_path = prefix_path / "package.json"
    existing_package = JSON.parse(File.read(package_path)) if File.readable?(package_path)

    unless init_config.yes
      puts <<-TEXT
        This utility will walk you through creating a package.json file.
        TEXT

      if existing_package
        puts <<-TEXT

          It looks like you already have a package.json file.
          The default values will be the ones in your existing file.

          TEXT
      else
        puts "It only covers the most common items, and tries to guess sensible defaults."
      end

      puts <<-TEXT

        Press ^C at any time to quit.


        TEXT
    end

    name = read_field(existing_package, "name") || Path.new(Dir.current).basename.to_s
    prompt("package name", name)

    version = read_field(existing_package, "version") || "0.0.1"
    prompt("version", version)

    description = read_field(existing_package, "description") || ""
    prompt("description", description)

    entry_point = read_field(existing_package, "main") || "index.js"
    prompt("entry point", entry_point)

    test_command = read_field(existing_package, "scripts", "tests") || ""
    prompt("test command", test_command)

    git_repository = read_field(existing_package, "repository") || ""
    prompt("git repository", git_repository)

    keywords = read_field(existing_package, "keywords") || ""
    prompt("keywords", keywords)
    keywords = keywords.to_s.split(/\s+/).reject(&.empty?).map { |k| JSON::Any.new(k) }

    author = read_field(existing_package, "author") || ""
    prompt("author", author)

    license = read_field(existing_package, "license") || "ISC"
    prompt("license", license)

    package = existing_package.try(&.as_h) || {} of String => JSON::Any
    package["name"] = JSON::Any.new(name)
    package["version"] = JSON::Any.new(version)
    package["description"] = JSON::Any.new(description)
    package["main"] = JSON::Any.new(entry_point)
    scripts = package["scripts"]? || JSON::Any.new({} of String => JSON::Any)
    scripts.as_h["test"] = JSON::Any.new(test_command)
    package["scripts"] = scripts
    package["repository"] = JSON::Any.new(git_repository)
    package["keywords"] = JSON::Any.new(keywords)
    package["author"] = JSON::Any.new(author)
    package["license"] = JSON::Any.new(license)

    reply = nil
    puts package.to_pretty_json
    puts ""
    unless init_config.yes
      print "About to write to #{package_path}.\nIs this OK? (yes)"
      reply = gets
    end

    if !reply || reply.empty? || reply.starts_with?("y")
      puts "Writing package.json…"
      File.write(package_path, package.to_pretty_json)
      puts "Done!"
    else
      puts "Aborting."
    end
  end
end

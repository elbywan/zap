#! /usr/bin/env crystal

require "option_parser"
require "colorize"
require "wait_group"
require "yaml"

project_filter = nil
command = "shards"
subcommand = "install"
parallel = false

OptionParser.parse do |parser|
  parser.banner = "Usage: ./projects.cr <--project=name> <install|build|spec> [options]"
  parser.on("-p", "--project=NAME", "Filter to a single project") { |name| project_filter = name }
  parser.on("-h", "--help", "Show this help") do
    puts parser
    exit
  end

  parser.invalid_option do
    parser.stop
  end

  parser.before_each do |arg|
    if !parser.@handlers.keys.includes?(arg)
      subcmd, *project_name = arg.split(":", 2)
      case subcmd
      when "install"
        command = "shards"
        subcommand = "install"
      when "build"
        command = "shards"
        subcommand = "build"
      when "run"
        command = "shards"
        subcommand = "run"
      when "spec"
        command = "crystal"
        subcommand = "spec"
      when "bump"
        command = "@@"
        subcommand = "bump"
      end
      project_filter = project_name[0] if project_name.size == 1
      ARGV.shift
      parser.stop
    end
  end
end

extra_args = ARGV.map { |s| s.includes?(" ") ? %("#{s.gsub('"', "\"")}") : s }.join(" ")
full_command = "#{command} #{subcommand} #{extra_args}"

projects = Dir["#{Path.posix(Path.new(__DIR__)).normalize}/**/shard.yml"]
  .each
  .map(&->File.dirname(String))
  .reject { |file|
    Path.new(file).parent.basename == "lib"
  }
  .map { |project_path|
    shard_yml = YAML.parse(File.read("#{project_path}/shard.yml"))
    {path: project_path, name: shard_yml.dig("name").as_s, shard_yml: shard_yml}
  }
  .select { |project| project_filter.nil? || project[:name] == project_filter }
  .to_a
  .sort_by { |project| project[:name] }

print "🔎 Found #{projects.size} project(s): ".colorize.bold
if project_filter
  print "= #{project_filter.colorize.bold}".colorize.italic.dim
end
print "\n"
puts projects.map { |project| "  - #{project[:name].colorize.bold.cyan} (#{project[:path]})" }.join("\n")
puts

puts "🚀 Running command: #{full_command.colorize.yellow}".colorize.bold
puts

wg = WaitGroup.new(projects.size) if parallel

run_command = ->(project : {path: String, name: String, shard_yml: YAML::Any}) do
  project_path, project_name, shard_yml = project[:path], project[:name], project[:shard_yml]

  if command == "@@"
    full_command = "#{command} #{project_path}"
    case subcommand
    when "bump"
      new_version = ARGV[0]?
      if new_version.nil?
        puts "❌ No version specified for bumping.".colorize.red.bold
        exit 1
      end
      shard_yml.as_h[YAML::Any.new("version")] = YAML::Any.new(new_version)
      File.write("#{project_path}/shard.yml", shard_yml.to_yaml)
      puts "✅ Bumped version of #{project_name} to #{new_version}".colorize.green.bold
    else
      raise "Unknown subcommand: #{subcommand}"
    end
  else
    buffer = IO::Memory.new
    status = Process.run(
      full_command,
      shell: true,
      chdir: project_path,
      output: buffer,
      error: buffer
    )

    if status.success?
      puts "✅ #{project_name}".colorize.green.bold
      puts buffer.rewind.gets_to_end if buffer.size > 0
    else
      puts "❌ #{project_name}".colorize.red.bold
      puts buffer.rewind.gets_to_end if buffer.size > 0
      raise %(Failed to run command "#{full_command}" for project #{project_name} with exit code #{status.exit_code}")
    end
  end
ensure
  wg.done if wg
end

exit_status = 0

projects.each do |project|
  if parallel
    spawn do
      run_command.call(project)
    rescue e
      exit_status = 1
    end
  else
    run_command.call(project)
  end
end

wg.wait if wg

Process.exit(exit_status)

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
      end
      project_filter = project_name[0] if project_name.size == 1
      ARGV.shift
      parser.stop
    end
  end
end

extra_args = ARGV.join(" ")
full_command = "#{command} #{subcommand} #{extra_args}"

projects = Dir["./**/shard.yml"]
  .each
  .map(&->File.dirname(String))
  .reject { |file|
    Path.new(file).parent.basename == "lib"
  }
  .map { |project_path|
    {path: project_path, name: YAML.parse(File.read("#{project_path}/shard.yml")).dig("name").as_s}
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

run_command = ->(project : {path: String, name: String}) do
  project_path, project_name = project[:path], project[:name]
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
    raise "Failed to run command for project #{project_name} with exit code #{status.exit_code}"
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

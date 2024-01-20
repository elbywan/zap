src_dir = Path.new({{ __DIR__ }}, "../src").expand
target_filenames = Dir["#{src_dir}/**/*_spec.cr"]
target_filenames.each { |filename|
  relative_path = Path.new(filename).relative_to({{__DIR__}})
  puts "#{relative_path}\n"
}

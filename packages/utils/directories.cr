module Utils::Directories
  def self.mkdir_p(path : Path | String, mode = 0o777) : Nil
    return if Dir.exists?(path)

    path = Path.new path

    path.each_parent do |parent|
      Dir.mkdir(parent, mode)
    rescue ::File::AlreadyExistsError | ::File::AccessDeniedError
      # ignore
    end
    Dir.mkdir(path, mode)
  rescue ::File::AlreadyExistsError | ::File::AccessDeniedError
    # ignore
  end
end

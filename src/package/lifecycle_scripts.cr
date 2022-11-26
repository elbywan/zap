class Zap::Package
  class LifecycleScripts
    include JSON::Serializable
    include YAML::Serializable

    Utils::Macros.define_field_accessors

    getter preinstall : String?
    property install : String?
    getter postinstall : String?

    getter preprepare : String?
    getter prepare : String?
    getter postprepare : String?

    getter prepublishOnly : String?
    getter prepublish : String?
    getter postpublish : String?

    getter prepack : String?
    getter postpack : String?

    getter dependencies : String?

    def initialize
    end

    def no_scripts?
      !preinstall && !install && !postinstall &&
        !preprepare && !prepare && !postprepare &&
        !prepublishOnly && !prepublish && !postpublish &&
        !prepack && !postpack &&
        !dependencies
    end

    def has_install_script?
      !install.nil? || nil
    end

    def has_prepare_script?
      !prepare.nil? || nil
    end

    def has_self_install_lifecycle?
      !!install ||
        !!prepublish ||
        !!prepare
    end

    def run_script(kind : Symbol, chdir : Path | String, config : Config, raise_on_error_code = true, output_io = nil, **args)
      field(kind).try do |command|
        output = output_io || IO::Memory.new
        # See: https://docs.npmjs.com/cli/v9/commands/npm-run-script
        env = {
          "PATH" => config.bin_path + Process::PATH_DELIMITER + config.node_path + Process::PATH_DELIMITER + ENV["PATH"],
        }
        yield command
        status = Process.run(command, **args, shell: true, env: env, chdir: chdir, output: output, error: output)
        if !status.success? && raise_on_error_code
          raise "#{output_io ? "" : output}\nCommand failed: #{command} (#{status.exit_status})"
        end
      end
    end

    def run_script(kind : Symbol, chdir : Path | String, config : Config, raise_on_error_code = true, output_io = nil, **args)
      run_script(kind, chdir, config, raise_on_error_code, output_io, **args) { }
    end
  end
end

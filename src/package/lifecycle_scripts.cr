class Zap::Package
  struct LifecycleScripts
    include JSON::Serializable
    include YAML::Serializable

    getter preinstall : String?
    getter install : String?
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

    private macro get_script(kind)
      self.{{kind.id}}
    end

    def no_scripts?
      !preinstall && !install && !postinstall &&
        !preprepare && !prepare && !postprepare &&
        !prepublishOnly && !prepublish && !postpublish &&
        !prepack && !postpack &&
        !dependencies
    end

    def run_script(kind : Symbol | String, chdir : Path | String, config : Config, raise_on_error_code = true, **args)
      get_script(kind).try do |script|
        output = IO::Memory.new
        # See: https://docs.npmjs.com/cli/v9/commands/npm-run-script
        env = {
          :PATH => ENV["PATH"] + Process.PATH_DELIMITER + config.bin_path + Process.PATH_DELIMITER + config.node_path,
        }
        status = Process.run(script, **args, shell: true, env: env, chdir: chdir, output: output, error: output)
        if !status.success? && raise_on_error_code
          raise "#{output}\nCommand failed: #{command} (#{status.exit_status})"
        end
      end
    end
  end
end

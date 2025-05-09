require "json"
require "yaml"
require "msgpack"
require "./scripts"
require "utils/macros"

class Data::Package
  class LifecycleScripts
    include JSON::Serializable
    include YAML::Serializable
    include MessagePack::Serializable

    Utils::Macros.define_field_accessors

    getter build : String?

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
      !install.nil? || !postinstall.nil? || !preinstall.nil? || nil
    end

    def has_prepare_script?
      !prepare.nil? || nil
    end

    # See https://docs.npmjs.com/cli/v8/configuring-npm/package-json#git-urls-as-dependencies
    def has_install_from_git_related_scripts?
      !!build ||
        !!prepare ||
        !!prepack ||
        !!preinstall ||
        !!install ||
        !!postinstall
    end

    SELF_LIFECYCLE_SCRIPTS = %i(preinstall install postinstall prepublish preprepare prepare postprepare)

    def has_self_install_lifecycle?
      !!preinstall ||
        !!install ||
        !!postinstall ||
        !!prepublish ||
        !!prepare
    end

    def install_lifecycle_scripts : Array(Symbol)
      SELF_LIFECYCLE_SCRIPTS.map { |name|
        field(name) ? name : nil
      }.compact
    end

    def run_script(kind : Symbol, chdir : Path | String, config : Core::Config, raise_on_error_code : Bool = true, output_io : (IO | Process::Redirect)? = nil, **args, &block : String, Symbol ->)
      field(kind).try do |command|
        Scripts.run_script(command, chdir, config, raise_on_error_code, output_io, **args, &block)
      end
    end

    def run_script(kind : Symbol, chdir : Path | String, config : Core::Config, raise_on_error_code : Bool = true, output_io : (IO | Process::Redirect)? = nil, **args)
      run_script(kind, chdir.to_s, config, raise_on_error_code, output_io, **args) { }
    end
  end
end

class Crystal::Scheduler
  class_getter nb_of_workers = 1
  {% if flag?(:preview_mt) && !flag?(:execution_context) %}
    private def self.worker_count
      env_workers = ENV["CRYSTAL_WORKERS"]? || ENV["ZAP_WORKERS"]?

      @@nb_of_workers = if env_workers && !env_workers.empty?
                          workers = env_workers.to_i?
                          if !workers || workers < 1
                            Crystal::System.print_error "FATAL: Invalid value for CRYSTAL_WORKERS: #{env_workers}\n"
                            exit 1
                          end

                          workers
                        else
                          # Use as many number of logical cpu cores as possible, with a hard cap of 8
                          {System.cpu_count, 8}.min.to_i32
                        end
      @@nb_of_workers
    end
  {% end %}
end

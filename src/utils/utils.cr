module Zap::Utils
  macro ignore
    begin
      {{ yield }}
    rescue
      # ignore
    end
  end
end

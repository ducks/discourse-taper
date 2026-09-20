# frozen_string_literal: true

module DiscourseTaper
  class Engine < ::Rails::Engine
    engine_name PLUGIN_NAME
    isolate_namespace DiscourseTaper
  end
end

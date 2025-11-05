require "rake"

module Gitlab
  module Dangerfiles
    module TaskLoader
      module_function

      TASKS_DIR = File.expand_path("tasks", __dir__)

      def load_tasks
        Rake.application.add_import(*Dir.glob(File.join(TASKS_DIR, "*.rake")))
      end
    end
  end
end

# frozen_string_literal: true

module Labkit
  module Middleware
    # Middleware for sidekiq
    module Sidekiq
      autoload :Client, "labkit/middleware/sidekiq/client"
      autoload :Server, "labkit/middleware/sidekiq/server"
      autoload :Context, "labkit/middleware/sidekiq/context"
      autoload :Tracing, "labkit/middleware/sidekiq/tracing"
    end
  end
end

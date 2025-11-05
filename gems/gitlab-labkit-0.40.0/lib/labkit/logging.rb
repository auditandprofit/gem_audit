# frozen_string_literal: true

module Labkit
  # Logging provides functionality for logging, such as
  # sanitization
  module Logging
    autoload :GRPC, "labkit/logging/grpc"
    autoload :Sanitizer, "labkit/logging/sanitizer"
    autoload :JsonLogger, "labkit/logging/json_logger"
  end
end

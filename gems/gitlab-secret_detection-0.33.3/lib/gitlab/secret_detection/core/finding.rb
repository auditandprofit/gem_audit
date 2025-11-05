# frozen_string_literal: true

module Gitlab
  module SecretDetection
    module Core
      # Finding is a data object representing a secret finding identified within a payload
      class Finding
        attr_reader :payload_id, :status, :line_number, :type, :description

        def initialize(payload_id, status, line_number = nil, type = nil, description = nil)
          @payload_id = payload_id
          @status = status
          @line_number = line_number
          @type = type
          @description = description
        end

        def ==(other)
          self.class == other.class && other.state == state
        end

        def to_h
          {
            payload_id:,
            status:,
            line_number:,
            type:,
            description:
          }
        end

        protected

        def state
          [payload_id, status, line_number, type, description]
        end
      end
    end
  end
end

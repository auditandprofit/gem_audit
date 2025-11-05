# frozen_string_literal: true

require_relative "spin"

module Gitlab
  module Dangerfiles
    Approval = Struct.new(:category, :spin) do
      def self.from_approval_rule(rule, maintainer)
        category =
          if rule["section"] == "codeowners"
            "`#{rule['name']}`"
          else
            rule["section"]
          end.to_sym

        spin = Spin.new(category, nil, maintainer, :reviewer)

        new(category, spin)
      end
    end
  end
end

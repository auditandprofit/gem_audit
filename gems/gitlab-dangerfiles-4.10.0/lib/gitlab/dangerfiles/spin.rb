# frozen_string_literal: true

module Gitlab
  module Dangerfiles
    Spin = Struct.new(:category, :reviewer, :maintainer, :optional_role) do
      def no_reviewer?
        reviewer.nil?
      end

      def no_maintainer?
        maintainer.nil?
      end
    end
  end
end

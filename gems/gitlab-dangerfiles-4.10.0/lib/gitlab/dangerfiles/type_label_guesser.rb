# frozen_string_literal: true

module Gitlab
  module Dangerfiles
    class TypeLabelGuesser
      CHANGELOG_CATEGORY_TO_TYPE_LABEL = {
        fixed: %w[type::bug],
        security: %w[type::bug bug::vulnerability],
        performance: %w[type::bug bug::performance],
        added: %w[type::feature feature::addition],
        deprecated: %w[type::maintenance maintenance::removal],
        removed: %w[type::maintenance maintenance::removal]
      }.freeze

      def labels_from_changelog_categories(categories)
        categories = categories.map(&:to_sym) & CHANGELOG_CATEGORY_TO_TYPE_LABEL.keys
        return [] unless categories.one?

        CHANGELOG_CATEGORY_TO_TYPE_LABEL.fetch(categories.first.to_sym, [])
      end
    end
  end
end

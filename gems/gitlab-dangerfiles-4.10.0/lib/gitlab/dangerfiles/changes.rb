# frozen_string_literal: true

require_relative "title_linting"

module Gitlab
  module Dangerfiles
    # @!attribute file
    #   @return [String] the file name that's changed.
    # @!attribute change_type
    #   @return [Symbol] the type of change (+:added+, +:modified+, +:deleted+, +:renamed_before+, +:renamed_after+).
    # @!attribute category
    #   @return [Symbol] the category of the change.
    #     This is defined by consumers of the gem through +helper.changes_by_category+ or +helper.changes+.
    Change = Struct.new(:file, :change_type, :category)

    class Changes < ::SimpleDelegator
      # Return an +Gitlab::Dangerfiles::Changes+ object with only the changes for the added files.
      #
      # @return [Gitlab::Dangerfiles::Changes]
      def added
        select_by_change_type(:added)
      end

      # @return [Gitlab::Dangerfiles::Changes] the changes for the modified files.
      def modified
        select_by_change_type(:modified)
      end

      # @return [Gitlab::Dangerfiles::Changes] the changes for the deleted files.
      def deleted
        select_by_change_type(:deleted)
      end

      # @return [Gitlab::Dangerfiles::Changes] the changes for the renamed files (before the rename).
      def renamed_before
        select_by_change_type(:renamed_before)
      end

      # @return [Gitlab::Dangerfiles::Changes] the changes for the renamed files (after the rename).
      def renamed_after
        select_by_change_type(:renamed_after)
      end

      # @param category [Symbol] A category of change.
      #
      # @return [Boolean] whether there are any change for the given +category+.
      def has_category?(category)
        any? { |change| change.category == category }
      end

      # @param category [Symbol] a category of change.
      #
      # @return [Gitlab::Dangerfiles::Changes] changes for the given +category+.
      def by_category(category)
        Changes.new(select { |change| change.category == category })
      end

      # @return [Array<Symbol>] an array of the unique categories of changes.
      def categories
        map(&:category).uniq
      end

      # @return [Array<String>] an array of the changed files.
      def files
        map(&:file).uniq
      end

      private

      def select_by_change_type(change_type)
        Changes.new(select { |change| change.change_type == change_type })
      end
    end
  end
end

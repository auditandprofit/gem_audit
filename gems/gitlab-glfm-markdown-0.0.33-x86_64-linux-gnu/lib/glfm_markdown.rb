# frozen_string_literal: true

require_relative 'glfm_markdown/version'
require_relative 'glfm_markdown/loader'

load_rust_extension

module GLFMMarkdown
  GLFM_DEFAULT_OPTIONS = {
    autolink: true,
    escaped_char_spans: false,
    footnotes: true,
    full_info_string: true,
    gfm_quirks: true,
    github_pre_lang: false,
    hardbreaks: false,
    inapplicable_tasks: false,
    math_code: false,
    math_dollars: false,
    multiline_block_quotes: true,
    relaxed_autolinks: false,
    sourcepos: true,
    smart: false,
    strikethrough: true,
    table: true,
    tagfilter: false,
    tasklist: true,
    tasklist_classes: true,
    unsafe: true,

    debug: false
  }.freeze

  class << self
    def to_html(markdown, options: {})
      raise TypeError, 'markdown must be a String' unless markdown.is_a?(String)
      raise TypeError, 'markdown must be UTF-8 encoded' unless markdown.encoding.name == "UTF-8"
      raise TypeError, 'options must be a Hash' unless options.is_a?(Hash)

      default_options = options[:glfm] ? GLFM_DEFAULT_OPTIONS : {}

      # if you need to modify `options`, use `.merge` as `options` could be frozen
      options = options.merge(unsafe: true) if options[:tagfilter]

      render_to_html_rs(markdown, default_options.merge(options))
    end
  end
end

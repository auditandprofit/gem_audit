# frozen_string_literal: true

def load_rust_extension
  ruby_version = /(\d+\.\d+)/.match(RUBY_VERSION)
  require "glfm_markdown/#{ruby_version}/glfm_markdown"
rescue LoadError
  require 'glfm_markdown/glfm_markdown'
end

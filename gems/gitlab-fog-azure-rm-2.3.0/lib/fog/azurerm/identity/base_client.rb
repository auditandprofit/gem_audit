# frozen_string_literal: trues

require 'json'

module Fog
  module AzureRM
    module Identity
      # BaseClient is responsible for fetching credentials and refreshing
      # them when necessary.
      class BaseClient
        include Fog::AzureRM::Utilities::General
        attr_accessor :credentials

        FetchCredentialsError = Class.new(RuntimeError)

        DEFAULT_TIMEOUT_S = 30

        def fetch_credentials
          raise NotImplementedError
        end

        def fetch_credentials_if_needed
          @credentials = fetch_credentials if @credentials.nil? || refresh_needed?

          credentials
        end

        def refresh_needed?
          return true unless @credentials

          @credentials.refresh_needed?
        end

        protected

        def process_token_response(response)
          # If we get an unauthorized error, raising an exception allows the admin
          # diagnose the error with the federated credentials.
          raise FetchCredentialsError, response.to_s unless response.success?

          body = ::JSON.parse(response.body)
          access_token = body['access_token']

          return unless access_token

          expires_at = ::Time.now
          expires_on = body['expires_on']
          expires_at = ::Time.at(expires_on.to_i) if expires_on

          Credentials.new(access_token, expires_at)
        rescue ::JSON::ParserError # rubocop:disable Lint/SuppressedException
        end

        private

        def get(url, params: nil, headers: nil)
          Faraday.get(url, params, headers) do |req|
            req.options.timeout = DEFAULT_TIMEOUT_S
          end
        rescue ::Faraday::Error => e
          raise FetchCredentialsError, e.to_s
        end

        def post(url, body: nil, headers: nil)
          Faraday.post(url, body, headers) do |req|
            req.options.timeout = DEFAULT_TIMEOUT_S
          end
        rescue ::Faraday::Error => e
          raise FetchCredentialsError, e.to_s
        end
      end
    end
  end
end

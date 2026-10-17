# frozen_string_literal: true

require 'net/http'
require 'uri'

module Nondisposable
  # Downloads one source's body, refusing anything that would not fit or not
  # finish: the body is streamed, and the download is abandoned the moment it
  # crosses the source's `max_bytes` or its `deadline`. A slow or bottomless
  # response therefore costs at most one deadline, never a stuck job or a
  # worker's memory.
  #
  # No redirects are followed: every preset URL is a direct raw file, and a
  # redirect to somewhere else is not the list we decided to trust.
  module SourceFetcher
    class FetchError < StandardError; end

    OPEN_TIMEOUT = 10
    READ_TIMEOUT = 10

    class << self
      def fetch(source)
        uri = URI(source.url)
        started = monotonic
        body = +''

        Net::HTTP.start(
          uri.host,
          uri.port,
          use_ssl: uri.scheme == 'https',
          open_timeout: [OPEN_TIMEOUT, source.deadline].min,
          read_timeout: [READ_TIMEOUT, source.deadline].min
        ) do |http|
          http.max_retries = 0 if http.respond_to?(:max_retries=)

          http.request(Net::HTTP::Get.new(uri)) do |response|
            raise FetchError, "HTTP status #{response.code}" unless response.is_a?(Net::HTTPSuccess)

            declared = response['Content-Length'].to_i
            if declared > source.max_bytes
              raise FetchError, "declared size #{declared} bytes exceeds max_bytes #{source.max_bytes}"
            end

            response.read_body do |chunk|
              body << chunk
              raise FetchError, "body exceeds max_bytes #{source.max_bytes}" if body.bytesize > source.max_bytes
              raise FetchError, "download exceeded its #{source.deadline}s deadline" if monotonic - started > source.deadline
            end
          end
        end

        body.force_encoding(Encoding::UTF_8).scrub('')
      end

      private

      # Separate so tests can move time forward.
      def monotonic
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end
  end
end

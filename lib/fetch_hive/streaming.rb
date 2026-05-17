# frozen_string_literal: true

require "json"

module FetchHive
  # Lightweight Server-Sent Events (SSE) parser for streaming Fetch Hive responses.
  #
  # Sync example:
  #
  #   io = response.body  # any IO or string
  #   FetchHive::Streaming.parse_sse(io) do |event|
  #     puts event["content"] if event["type"] == "delta"
  #   end
  #
  module Streaming
    # Yields each parsed SSE event hash from +io_or_string+.
    # Stops when it encounters +data: [DONE]+ or the stream is exhausted.
    # Non-data lines, blank lines, and malformed JSON are silently skipped.
    #
    # @param io_or_string [String, IO, #each_line] the SSE response body
    # @yield [Hash] parsed JSON event
    def self.parse_sse(io_or_string, &block)
      return enum_for(:parse_sse, io_or_string) unless block

      buf = +""
      reader = io_or_string.respond_to?(:read) ? io_or_string : StringIO.new(io_or_string)

      loop do
        chunk = reader.read(4096)
        break if chunk.nil? || chunk.empty?

        buf << chunk

        while (idx = buf.index("\n"))
          line = buf.slice!(0, idx + 1).chomp
          next unless line.start_with?("data: ")

          payload = line[6..]
          return if payload.strip == "[DONE]"

          begin
            yield JSON.parse(payload)
          rescue JSON::ParserError
            # skip malformed lines
          end
        end
      end

      # Process any remaining buffer content after stream ends
      buf.each_line do |line|
        line = line.chomp
        next unless line.start_with?("data: ")

        payload = line[6..]
        next if payload.strip == "[DONE]"

        begin
          yield JSON.parse(payload)
        rescue JSON::ParserError
          # skip malformed lines
        end
      end
    end
  end
end

# frozen_string_literal: true

require "faraday"
require "json"
require_relative "streaming"

module FetchHive
  # Idiomatic facade over the OpenAPI-generated code.
  #
  # Usage:
  #
  #   client = FetchHive::Client.new(api_key: ENV["FETCH_HIVE_API_KEY"])
  #
  #   # Non-streaming prompt
  #   result = client.invoke_prompt(deployment: "my-prompt", inputs: { name: "Alice" })
  #   puts result["response"]
  #
  #   # Streaming agent
  #   client.invoke_agent_stream(agent: "my-agent", message: "Hello") do |chunk|
  #     case chunk["type"]
  #     when "response" then print chunk["response"]
  #     when "tool"     then puts "\nCalling tool: #{chunk['tool']}"
  #     when "usage"    then puts "\nUsage: #{chunk['usage']}"
  #     end
  #   end
  #
  class Client
    DEFAULT_BASE_URL = "https://api.fetchhive.com/v1"

    # @param api_key  [String, nil] Bearer token. Falls back to +FETCH_HIVE_API_KEY+ env var.
    # @param base_url [String]      Override the API base URL.
    # @param timeout  [Integer]     Request timeout in seconds (default: 120).
    def initialize(api_key: nil, base_url: DEFAULT_BASE_URL, timeout: 120)
      resolved = api_key || ENV["FETCH_HIVE_API_KEY"]
      raise ArgumentError, "api_key is required. Pass it explicitly or set FETCH_HIVE_API_KEY." if resolved.nil? || resolved.empty?

      @api_key  = resolved
      @base_url = base_url.to_s.sub(%r{/+\z}, "")
      @timeout  = timeout
    end

    # ── Prompt ─────────────────────────────────────────────────────────────────

    # Invoke a prompt deployment and return the full response hash.
    def invoke_prompt(deployment:, variant: nil, inputs: nil, user: nil, metadata: nil)
      body = { deployment: deployment, streaming: false }
      body[:variant] = variant if variant
      body[:inputs]  = inputs  if inputs
      body[:user]    = user    if user
      body[:metadata] = metadata if metadata
      post("/invoke", body)
    end

    # Invoke a prompt deployment and stream SSE events.
    # Yields each parsed event hash. Returns an Enumerator when no block given.
    def invoke_prompt_stream(deployment:, variant: nil, inputs: nil, user: nil, metadata: nil, &block)
      body = { deployment: deployment, streaming: true }
      body[:variant] = variant if variant
      body[:inputs]  = inputs  if inputs
      body[:user]    = user    if user
      body[:metadata] = metadata if metadata
      post_stream("/invoke", body, &block)
    end

    # ── Workflow ────────────────────────────────────────────────────────────────

    # Invoke a workflow deployment (sync or async).
    def invoke_workflow(deployment:, variant: nil, inputs: nil, async_mode: false, callback_url: nil, user: nil, metadata: nil)
      body = { deployment: deployment }
      body[:variant] = variant if variant
      body[:inputs]  = inputs  if inputs
      body[:user]    = user    if user
      body[:metadata] = metadata if metadata
      if async_mode
        body[:async] = { enabled: true }
        body[:async][:callback_url] = callback_url if callback_url
      end
      post("/workflow/invoke", body)
    end

    # ── Agent ───────────────────────────────────────────────────────────────────

    # Send a message to an agent and return the full response hash.
    def invoke_agent(agent:, message:, thread_id: nil, user: nil, metadata: nil, messages: nil, image_urls: nil)
      body = { agent: agent, message: message, streaming: false }
      body[:thread_id]  = thread_id  if thread_id
      body[:user]       = user       if user
      body[:metadata] = metadata if metadata
      body[:messages]   = messages   if messages
      body[:image_urls] = image_urls if image_urls
      post("/agent/invoke", body)
    end

    # Send a message to an agent and stream SSE events.
    # Yields each parsed event hash. Returns an Enumerator when no block given.
    def invoke_agent_stream(agent:, message:, thread_id: nil, user: nil, metadata: nil, messages: nil, image_urls: nil, &block)
      body = { agent: agent, message: message, streaming: true }
      body[:thread_id]  = thread_id  if thread_id
      body[:user]       = user       if user
      body[:metadata] = metadata if metadata
      body[:messages]   = messages   if messages
      body[:image_urls] = image_urls if image_urls
      post_stream("/agent/invoke", body, &block)
    end

    private

    def default_headers
      {
        "Authorization" => "Bearer #{@api_key}",
        "Content-Type"  => "application/json"
      }
    end

    def connection
      Faraday.new(url: @base_url, request: { timeout: @timeout }) do |f|
        f.adapter Faraday.default_adapter
      end
    end

    def post(path, body)
      resp = connection.post(path) do |req|
        req.headers.merge!(default_headers)
        req.body = JSON.generate(body)
      end
      raise "FetchHive API error #{resp.status}: #{resp.body}" unless resp.success?

      JSON.parse(resp.body)
    end

    def post_stream(path, body, &block)
      return enum_for(:post_stream, path, body) unless block

      io, writer = IO.pipe

      thread = Thread.new do
        conn = Faraday.new(url: @base_url, request: { timeout: @timeout }) do |f|
          f.adapter Faraday.default_adapter
        end

        resp = conn.post(path) do |req|
          req.headers.merge!(default_headers)
          req.body = JSON.generate(body)
          req.options.on_data = proc do |chunk, _size, env|
            if env && !env.status.between?(200, 299)
              writer.close
              raise "FetchHive API error #{env.status}: #{chunk}"
            end
            writer.write(chunk)
          end
        end

        unless resp.success?
          writer.close
          raise "FetchHive API error #{resp.status}: #{resp.body}"
        end

        writer.close
      end

      begin
        FetchHive::Streaming.parse_sse(io, &block)
      ensure
        io.close
        thread.join
      end
    end
  end
end

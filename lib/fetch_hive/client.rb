# frozen_string_literal: true

require "faraday"
require "json"
require "uri"
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
      post("/prompt/invoke", body)
    end

    # Invoke a prompt deployment and stream SSE events.
    # Yields each parsed event hash. Returns an Enumerator when no block given.
    def invoke_prompt_stream(deployment:, variant: nil, inputs: nil, user: nil, metadata: nil, &block)
      body = { deployment: deployment, streaming: true }
      body[:variant] = variant if variant
      body[:inputs]  = inputs  if inputs
      body[:user]    = user    if user
      body[:metadata] = metadata if metadata
      post_stream("/prompt/invoke", body, &block)
    end

    # ── Workflow ────────────────────────────────────────────────────────────────

    # Invoke a workflow deployment (sync or async).
    def invoke_workflow(deployment:, variant: nil, inputs: nil, async_mode: false, callback_url: nil, user: nil, metadata: nil, tool_approval: nil)
      body = { deployment: deployment }
      body[:variant] = variant if variant
      body[:inputs]  = inputs  if inputs
      body[:user]    = user    if user
      body[:metadata] = metadata if metadata
      body[:tool_approval] = tool_approval if tool_approval
      if async_mode
        body[:async] = { enabled: true }
        body[:async][:callback_url] = callback_url if callback_url
      end
      post("/workflow/invoke", body)
    end

    # ── Pipeline ────────────────────────────────────────────────────────────────

    # Starts a pipeline run. Always asynchronous: the result goes to callback_url, or with poll: true you follow it
    # with get_pipeline_run and get_pipeline_checkpoint. notify_checkpoints: false sends no checkpoint email or
    # Telegram message, for an app that shows checkpoints itself. Name a deployment (and optionally a variant), or a
    # pipeline id to run its default variant. Returns { "pipeline_run" => {...} }.
    def invoke_pipeline(callback_url: nil, deployment: nil, variant: nil, pipeline: nil, inputs: nil, max_spend_usd: nil,
                        poll: false, notify_checkpoints: nil)
      body = {}
      body[:deployment] = deployment if deployment
      body[:variant] = variant if variant
      body[:pipeline] = pipeline if pipeline
      body[:inputs] = inputs if inputs
      body[:max_spend_usd] = max_spend_usd if max_spend_usd
      body[:notify_checkpoints] = notify_checkpoints unless notify_checkpoints.nil?
      body[:async] = { enabled: true, callback_url: callback_url }
      body[:async][:poll] = true if poll
      post("/pipeline/invoke", body)
    end

    # Sets a pipeline template up in this API key's workspace and deploys it. Safe to call before every run: when
    # the workspace has it already, the same pipeline and deployment come back with "installed" => false.
    def install_pipeline_template(template_id:, deployment: nil)
      body = {}
      body[:deployment] = deployment if deployment
      post("/pipeline/templates/#{template_id}/install", body)
    end

    # A deployed pipeline's start inputs, stages, checkpoints and estimated cost per run.
    def get_pipeline(pipeline_id:, variant: nil)
      request("GET", pipeline_query("/pipeline/pipelines/#{pipeline_id}", [["variant", variant]]))
    end

    # The same as get_pipeline, by deployment key.
    def get_pipeline_deployment(deployment:, variant: nil)
      request("GET", pipeline_query("/pipeline/deployments/#{deployment}", [["variant", variant]]))
    end

    # Earlier pipeline runs, newest first, with their start inputs. per_page is up to 50.
    def list_pipeline_runs(pipeline: nil, deployment: nil, status: nil, page: nil, per_page: nil)
      pairs = [["pipeline", pipeline], ["deployment", deployment], ["status", status], ["page", page],
               ["per_page", per_page]]
      request("GET", pipeline_query("/pipeline/runs", pairs))
    end

    def get_pipeline_run(run_id:)
      request("GET", "/pipeline/runs/#{run_id}")
    end

    # What the run is waiting for at a checkpoint, and the answer shape to send.
    def get_pipeline_checkpoint(run_id:)
      request("GET", "/pipeline/runs/#{run_id}/checkpoint")
    end

    # request_id is the id of the checkpoint you were answering, so a late retry never lands on a later one.
    def answer_pipeline_checkpoint(run_id:, answer:, request_id: nil, node_key: nil)
      body = { answer: answer }
      body[:request_id] = request_id if request_id
      body[:node_key] = node_key if node_key
      post("/pipeline/runs/#{run_id}/checkpoint/answer", body)
    end

    def cancel_pipeline_run(run_id:)
      post("/pipeline/runs/#{run_id}/cancel", {})
    end

    # What a re-run with these changes would reuse and run, and its cost. Starts nothing.
    def plan_pipeline_revision(run_id:, changes:)
      post("/pipeline/runs/#{run_id}/revisions/plan", { changes: changes })
    end

    # Re-run a finished run with changes. Pass confirmed: true once the person agreed to the plan's cost.
    def create_pipeline_revision(run_id:, changes:, confirmed: false, callback_url: nil, max_spend_usd: nil)
      body = { changes: changes, confirmed: confirmed }
      body[:callback_url] = callback_url if callback_url
      body[:max_spend_usd] = max_spend_usd if max_spend_usd
      post("/pipeline/runs/#{run_id}/revisions", body)
    end

    # ── Agent ───────────────────────────────────────────────────────────────────

    # Send a message to an agent and return the full response hash.
    def invoke_agent(agent:, message:, thread_id: nil, user: nil, metadata: nil, messages: nil, image_urls: nil, attachments: nil, known_artifact_refs: nil, artifact_refs: nil, async: nil, tool_approval: nil)
      body = { agent: agent, message: message, streaming: false }
      body[:thread_id]  = thread_id  if thread_id
      body[:user]       = user       if user
      body[:metadata] = metadata if metadata
      body[:messages]   = messages   if messages
      body[:attachments] = attachments || image_urls if attachments || image_urls
      body[:known_artifact_refs] = known_artifact_refs if known_artifact_refs
      body[:artifact_refs] = artifact_refs if artifact_refs
      body[:tool_approval] = tool_approval if tool_approval
      body[:async] = async if async
      post("/agent/invoke", body)
    end

    # Send a message to an agent and stream SSE events.
    # Yields each parsed event hash. Returns an Enumerator when no block given.
    def invoke_agent_stream(agent:, message:, thread_id: nil, user: nil, metadata: nil, messages: nil, image_urls: nil, attachments: nil, known_artifact_refs: nil, artifact_refs: nil, tool_approval: nil, &block)
      body = { agent: agent, message: message, streaming: true }
      body[:thread_id]  = thread_id  if thread_id
      body[:user]       = user       if user
      body[:metadata] = metadata if metadata
      body[:messages]   = messages   if messages
      body[:attachments] = attachments || image_urls if attachments || image_urls
      body[:known_artifact_refs] = known_artifact_refs if known_artifact_refs
      body[:artifact_refs] = artifact_refs if artifact_refs
      body[:tool_approval] = tool_approval if tool_approval
      post_stream("/agent/invoke", body, &block)
    end

    # ── Hive Agent ──────────────────────────────────────────────────────────────

    # Start a Hive Agent run asynchronously. Requires a callback URL.
    def invoke_hive_agent(hive_agent:, objective:, callback_url:, sources: nil, metadata: nil, unattended: nil, budget_policy: nil)
      raise ArgumentError, "callback_url is required for Hive Agent invocation" if callback_url.nil? || callback_url.to_s.strip.empty?

      body = {
        hive_agent: hive_agent,
        objective: objective,
        async: { enabled: true, callback_url: callback_url }
      }
      body[:sources] = sources if sources
      body[:metadata] = metadata if metadata
      body[:unattended] = unattended unless unattended.nil?
      body[:budget_policy] = budget_policy if budget_policy
      post("/hive-agent/invoke", body)
    end

    # ── Public resources ────────────────────────────────────────────────────────

    def get_request(id:)
      request("GET", "/public/requests/#{id}")
    end

    def get_agent_delegation(id:)
      request("GET", "/agent/delegations/#{id}")
    end

    def cancel_agent_delegation(id:)
      post("/agent/delegations/#{id}/cancel", {})
    end

    def list_thread_delegations(thread_id:)
      request("GET", "/agent/threads/#{thread_id}/delegations")
    end

    # List tool-action approvals. The server defaults status to pending.
    def list_tool_action_approvals(workspace_id:, status: nil, agent_id: nil, run_id: nil, request_id: nil, cursor: nil, limit: nil)
      pairs = []
      pairs << ["status", status] if status
      pairs << ["agent_id", agent_id] if agent_id
      pairs << ["run_id", run_id] if run_id
      pairs << ["request_id", request_id] if request_id
      pairs << ["cursor", cursor] if cursor
      pairs << ["limit", limit] unless limit.nil?
      path = "/public/workspaces/#{workspace_id}/tool_action_approvals"
      path = "#{path}?#{URI.encode_www_form(pairs)}" unless pairs.empty?
      request("GET", path)
    end

    def get_tool_action_approval(workspace_id:, id:)
      request("GET", "/public/workspaces/#{workspace_id}/tool_action_approvals/#{id}")
    end

    # decision is "allow_once" or "deny". An API-key run resumes on the server.
    def decide_tool_action_approval(workspace_id:, id:, decision:)
      post("/public/workspaces/#{workspace_id}/tool_action_approvals/#{id}/decide", { decision: decision })
    end

    def list_knowledge_bases(workspace_id:)
      request("GET", "/public/workspaces/#{workspace_id}/knowledge_bases")
    end

    def get_knowledge_base(workspace_id:, id:)
      request("GET", "/public/workspaces/#{workspace_id}/knowledge_bases/#{id}")
    end

    def create_knowledge_base(workspace_id:, knowledge_base:)
      post("/public/workspaces/#{workspace_id}/knowledge_bases", { knowledge_base: knowledge_base })
    end

    def update_knowledge_base(workspace_id:, id:, knowledge_base:)
      request("PATCH", "/public/workspaces/#{workspace_id}/knowledge_bases/#{id}", { knowledge_base: knowledge_base })
    end

    def delete_knowledge_base(workspace_id:, id:)
      request("DELETE", "/public/workspaces/#{workspace_id}/knowledge_bases/#{id}")
    end

    def search_knowledge_base(workspace_id:, id:, **params)
      post("/public/workspaces/#{workspace_id}/knowledge_bases/#{id}/search", params)
    end

    def list_knowledge_base_items(workspace_id:, knowledge_base_id:)
      request("GET", "/public/workspaces/#{workspace_id}/knowledge_bases/#{knowledge_base_id}/items")
    end

    def get_knowledge_base_item(workspace_id:, knowledge_base_id:, id:)
      request("GET", "/public/workspaces/#{workspace_id}/knowledge_bases/#{knowledge_base_id}/items/#{id}")
    end

    def create_knowledge_base_item(workspace_id:, knowledge_base_id:, knowledge_base_item:)
      post("/public/workspaces/#{workspace_id}/knowledge_bases/#{knowledge_base_id}/items", { knowledge_base_item: knowledge_base_item })
    end

    def update_knowledge_base_item(workspace_id:, knowledge_base_id:, id:, knowledge_base_item:)
      request("PATCH", "/public/workspaces/#{workspace_id}/knowledge_bases/#{knowledge_base_id}/items/#{id}", { knowledge_base_item: knowledge_base_item })
    end

    def delete_knowledge_base_item(workspace_id:, knowledge_base_id:, id:)
      request("DELETE", "/public/workspaces/#{workspace_id}/knowledge_bases/#{knowledge_base_id}/items/#{id}")
    end

    def regenerate_knowledge_base_item(workspace_id:, knowledge_base_id:, id:)
      post("/public/workspaces/#{workspace_id}/knowledge_bases/#{knowledge_base_id}/items/#{id}/regenerate", {})
    end

    def list_agents(workspace_id:)
      request("GET", "/public/workspaces/#{workspace_id}/agents")
    end

    def get_agent(workspace_id:, id:)
      request("GET", "/public/workspaces/#{workspace_id}/agents/#{id}")
    end

    def create_agent(workspace_id:, agent:)
      post("/public/workspaces/#{workspace_id}/agents", { agent: agent })
    end

    def update_agent(workspace_id:, id:, agent:)
      request("PATCH", "/public/workspaces/#{workspace_id}/agents/#{id}", { agent: agent })
    end

    def delete_agent(workspace_id:, id:)
      request("DELETE", "/public/workspaces/#{workspace_id}/agents/#{id}")
    end

    def get_agent_chat(workspace_id:, agent_id:, chat_id:)
      request("GET", "/public/workspaces/#{workspace_id}/agents/#{agent_id}/chats/#{chat_id}")
    end

    def create_agent_chat(workspace_id:, agent_id:, chat:)
      post("/public/workspaces/#{workspace_id}/agents/#{agent_id}/chats", { chat: chat })
    end

    def update_agent_chat(workspace_id:, agent_id:, chat_id:, chat:)
      request("PATCH", "/public/workspaces/#{workspace_id}/agents/#{agent_id}/chats/#{chat_id}", { chat: chat })
    end

    def delete_agent_chat(workspace_id:, agent_id:, chat_id:)
      request("DELETE", "/public/workspaces/#{workspace_id}/agents/#{agent_id}/chats/#{chat_id}")
    end

    def clear_agent_chat_messages(workspace_id:, agent_id:, chat_id:)
      request("PATCH", "/public/workspaces/#{workspace_id}/agents/#{agent_id}/chats/#{chat_id}/clear_messages", {})
    end

    def list_agent_chat_messages(workspace_id:, agent_id:, chat_id:)
      request("GET", "/public/workspaces/#{workspace_id}/agents/#{agent_id}/chats/#{chat_id}/messages")
    end

    private

    def pipeline_query(path, pairs)
      present = pairs.reject { |_key, value| value.nil? || value == "" }
      present.empty? ? path : "#{path}?#{URI.encode_www_form(present)}"
    end

    def default_headers
      {
        "Authorization" => "Bearer #{@api_key}",
        "Content-Type"  => "application/json"
      }
    end

    def connection
      # Build Faraday without a url prefix. Absolute paths like `/prompt/invoke`
      # replace Faraday's prefix path (`/v1`), which would drop `/v1` from the URL.
      Faraday.new(request: { timeout: @timeout }) do |f|
        f.adapter Faraday.default_adapter
      end
    end

    def full_url(path)
      "#{@base_url}#{path}"
    end

    def post(path, body)
      request("POST", path, body)
    end

    def request(method, path, body = nil)
      resp = connection.run_request(method.downcase.to_sym, full_url(path), body && JSON.generate(body), default_headers)
      raise "FetchHive API error #{resp.status}: #{resp.body}" unless resp.success?
      return {} if resp.body.nil? || resp.body.empty?

      JSON.parse(resp.body)
    end

    def post_stream(path, body, &block)
      return enum_for(:post_stream, path, body) unless block

      io, writer = IO.pipe

      thread = Thread.new do
        conn = Faraday.new(request: { timeout: @timeout }) do |f|
          f.adapter Faraday.default_adapter
        end

        resp = conn.post(full_url(path)) do |req|
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

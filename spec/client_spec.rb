# frozen_string_literal: true

require "spec_helper"
require "fetch_hive"

RSpec.describe FetchHive::Client do
  let(:api_key)   { "fhk_test_ruby_key" }
  let(:base_url)  { "https://api.fetchhive.com/v1" }
  let(:client)    { described_class.new(api_key: api_key) }

  # ── Construction ─────────────────────────────────────────────────────────────

  # C1 — Missing API key with no env var raises with a clear message
  describe "C1: missing api_key raises" do
    it "raises ArgumentError with a descriptive message" do
      with_env("FETCH_HIVE_API_KEY" => nil) do
        expect { described_class.new(api_key: nil) }
          .to raise_error(ArgumentError, /api_key is required/)
      end
    end

    it "raises when api_key is empty string and env var is absent" do
      with_env("FETCH_HIVE_API_KEY" => nil) do
        expect { described_class.new(api_key: "") }
          .to raise_error(ArgumentError, /api_key is required/)
      end
    end
  end

  # C2 — FETCH_HIVE_API_KEY env var used as fallback
  describe "C2: FETCH_HIVE_API_KEY env var fallback" do
    it "reads the key from the environment when no explicit key is passed" do
      stub_request(:post, "#{base_url}/prompt/invoke")
        .to_return(status: 200, body: '{"response":"ok"}', headers: { "Content-Type" => "application/json" })

      with_env("FETCH_HIVE_API_KEY" => "fhk_from_env") do
        c = described_class.new
        result = c.invoke_prompt(deployment: "dep")
        expect(result["response"]).to eq("ok")
      end
    end
  end

  # C3 — Custom base_url is used for requests
  describe "C3: custom base_url" do
    it "sends requests to the overridden base URL" do
      stub = stub_request(:post, "https://custom.example.com/v1/prompt/invoke")
        .to_return(status: 200, body: '{"response":"custom"}', headers: { "Content-Type" => "application/json" })

      c = described_class.new(api_key: api_key, base_url: "https://custom.example.com/v1")
      c.invoke_prompt(deployment: "dep")
      expect(stub).to have_been_requested
    end
  end

  # C4 — Trailing slash on base_url is stripped
  describe "C4: trailing slash stripped from base_url" do
    it "does not produce double slashes in the request path" do
      stub = stub_request(:post, "https://api.fetchhive.com/v1/prompt/invoke")
        .to_return(status: 200, body: '{"response":"ok"}', headers: { "Content-Type" => "application/json" })

      c = described_class.new(api_key: api_key, base_url: "https://api.fetchhive.com/v1/")
      c.invoke_prompt(deployment: "dep")
      expect(stub).to have_been_requested
    end
  end

  # C5 — Default base URL
  describe "C5: default base URL" do
    it "uses https://api.fetchhive.com/v1 by default" do
      stub = stub_request(:post, "#{base_url}/prompt/invoke")
        .to_return(status: 200, body: '{"response":"ok"}', headers: { "Content-Type" => "application/json" })

      client.invoke_prompt(deployment: "dep")
      expect(stub).to have_been_requested
    end
  end

  # ── Auth ─────────────────────────────────────────────────────────────────────

  # A1 — Authorization header sent on every request
  describe "A1: Authorization header" do
    it "sends Authorization: Bearer <key> on every request" do
      stub_request(:post, "#{base_url}/prompt/invoke")
        .with(headers: { "Authorization" => "Bearer #{api_key}" })
        .to_return(status: 200, body: '{"response":"ok"}', headers: { "Content-Type" => "application/json" })

      expect { client.invoke_prompt(deployment: "dep") }.not_to raise_error
    end
  end

  # A2 — Content-Type header sent
  describe "A2: Content-Type header" do
    it "sends Content-Type: application/json" do
      stub_request(:post, "#{base_url}/prompt/invoke")
        .with(headers: { "Content-Type" => "application/json" })
        .to_return(status: 200, body: '{"response":"ok"}', headers: { "Content-Type" => "application/json" })

      expect { client.invoke_prompt(deployment: "dep") }.not_to raise_error
    end
  end

  # ── Prompt ────────────────────────────────────────────────────────────────────

  # P1 — invoke_prompt POSTs to /prompt/invoke
  describe "P1: invoke_prompt endpoint" do
    it "POSTs to /prompt/invoke" do
      stub = stub_request(:post, "#{base_url}/prompt/invoke")
        .to_return(status: 200, body: '{"response":"ok"}', headers: { "Content-Type" => "application/json" })

      client.invoke_prompt(deployment: "dep")
      expect(stub).to have_been_requested
    end
  end

  # P2 — invoke_prompt returns parsed JSON body
  describe "P2: invoke_prompt returns parsed JSON" do
    it "returns a Hash with the response body" do
      stub_request(:post, "#{base_url}/prompt/invoke")
        .to_return(status: 200, body: '{"response":"Hello","request_id":"r1"}', headers: { "Content-Type" => "application/json" })

      result = client.invoke_prompt(deployment: "dep")
      expect(result).to eq("response" => "Hello", "request_id" => "r1")
    end
  end

  # P3 — streaming: false injected; optional fields only when provided
  describe "P3: invoke_prompt body shape" do
    it "injects streaming: false and omits absent optional fields" do
      stub = stub_request(:post, "#{base_url}/prompt/invoke")
        .with(body: hash_including("deployment" => "dep", "streaming" => false))
        .to_return(status: 200, body: "{}", headers: { "Content-Type" => "application/json" })

      client.invoke_prompt(deployment: "dep")
      expect(stub).to have_been_requested
    end

    it "includes variant, inputs, user, and metadata when provided" do
      stub = stub_request(:post, "#{base_url}/prompt/invoke")
        .with(body: hash_including(
          "variant" => "v2",
          "inputs" => { "k" => "v" },
          "user" => "u1",
          "metadata" => { "customer_id" => "cus_123", "trial" => false, "invoice_count" => 12, "region" => nil }
        ))
        .to_return(status: 200, body: "{}", headers: { "Content-Type" => "application/json" })

      client.invoke_prompt(
        deployment: "dep",
        variant: "v2",
        inputs: { k: "v" },
        user: "u1",
        metadata: { customer_id: "cus_123", trial: false, invoice_count: 12, region: nil }
      )
      expect(stub).to have_been_requested
    end

    it "omits variant, inputs, and user when not provided" do
      stub = stub_request(:post, "#{base_url}/prompt/invoke")
        .to_return(status: 200, body: "{}", headers: { "Content-Type" => "application/json" })

      client.invoke_prompt(deployment: "dep")
      expect(a_request(:post, "#{base_url}/prompt/invoke").with { |req|
        body = JSON.parse(req.body)
        %w[variant inputs user metadata].none? { |k| body.key?(k) }
      }).to have_been_made
    end
  end

  # ── Workflow ──────────────────────────────────────────────────────────────────

  # W1 — invoke_workflow POSTs to /workflow/invoke
  describe "W1: invoke_workflow endpoint" do
    it "POSTs to /workflow/invoke" do
      stub = stub_request(:post, "#{base_url}/workflow/invoke")
        .to_return(status: 200, body: '{"status":"completed"}', headers: { "Content-Type" => "application/json" })

      client.invoke_workflow(deployment: "wf")
      expect(stub).to have_been_requested
    end
  end

  # W2 — invoke_workflow returns parsed JSON body
  describe "W2: invoke_workflow returns parsed JSON" do
    it "returns a Hash" do
      stub_request(:post, "#{base_url}/workflow/invoke")
        .to_return(status: 200, body: '{"status":"completed","run_id":"run1"}', headers: { "Content-Type" => "application/json" })

      result = client.invoke_workflow(deployment: "wf")
      expect(result).to eq("status" => "completed", "run_id" => "run1")
    end
  end

  # W3 — Async mode + callback URL
  describe "W3: async mode body shape" do
    it "builds the async block with enabled: true and callback_url" do
      stub = stub_request(:post, "#{base_url}/workflow/invoke")
        .with(body: hash_including("async" => { "enabled" => true, "callback_url" => "https://cb.example.com" }))
        .to_return(status: 200, body: '{"status":"queued"}', headers: { "Content-Type" => "application/json" })

      client.invoke_workflow(deployment: "wf", async_mode: true, callback_url: "https://cb.example.com")
      expect(stub).to have_been_requested
    end

    it "omits async block when async_mode is false" do
      stub = stub_request(:post, "#{base_url}/workflow/invoke")
        .to_return(status: 200, body: '{"status":"completed"}', headers: { "Content-Type" => "application/json" })

      client.invoke_workflow(deployment: "wf")
      expect(a_request(:post, "#{base_url}/workflow/invoke").with { |req|
        !JSON.parse(req.body).key?("async")
      }).to have_been_made
    end

    it "passes metadata through" do
      stub = stub_request(:post, "#{base_url}/workflow/invoke")
        .with(body: hash_including("metadata" => { "customer_id" => "cus_123", "invoice_count" => 12 }))
        .to_return(status: 200, body: '{"status":"completed"}', headers: { "Content-Type" => "application/json" })

      client.invoke_workflow(deployment: "wf", metadata: { customer_id: "cus_123", invoice_count: 12 })
      expect(stub).to have_been_requested
    end
  end

  # ── Agent ─────────────────────────────────────────────────────────────────────

  # AG1 — invoke_agent POSTs to /agent/invoke with streaming: false
  describe "AG1: invoke_agent endpoint and streaming flag" do
    it "POSTs to /agent/invoke with streaming: false" do
      stub = stub_request(:post, "#{base_url}/agent/invoke")
        .with(body: hash_including("streaming" => false))
        .to_return(status: 200, body: '{"response":"ok"}', headers: { "Content-Type" => "application/json" })

      client.invoke_agent(agent: "ag", message: "hi")
      expect(stub).to have_been_requested
    end
  end

  # AG2 — invoke_agent returns parsed JSON body
  describe "AG2: invoke_agent returns parsed JSON" do
    it "returns a Hash with the response body" do
      stub_request(:post, "#{base_url}/agent/invoke")
        .to_return(status: 200, body: '{"response":"hello","thread_id":"t1"}', headers: { "Content-Type" => "application/json" })

      result = client.invoke_agent(agent: "ag", message: "hi")
      expect(result).to eq("response" => "hello", "thread_id" => "t1")
    end
  end

  # AG3 — Optional fields included only when provided
  describe "AG3: invoke_agent optional fields" do
    it "includes thread_id, user, metadata, messages, attachments, and artifact refs when provided" do
      stub = stub_request(:post, "#{base_url}/agent/invoke")
        .with(body: hash_including(
          "thread_id"  => "t1",
          "user"       => "u1",
          "metadata" => { "customer_id" => "cus_123", "trial" => false },
          "messages"   => [{ "role" => "user", "content" => "hi" }],
          "attachments" => ["https://img.example.com/a.png"],
          "known_artifact_refs" => ["11111111-1111-4111-8111-111111111111"],
          "artifact_refs" => ["11111111-1111-4111-8111-111111111111"]
        ))
        .to_return(status: 200, body: '{"response":"ok"}', headers: { "Content-Type" => "application/json" })

      client.invoke_agent(
        agent: "ag", message: "hi",
        thread_id: "t1", user: "u1",
        metadata: { customer_id: "cus_123", trial: false },
        messages: [{ role: "user", content: "hi" }],
        attachments: ["https://img.example.com/a.png"],
        known_artifact_refs: ["11111111-1111-4111-8111-111111111111"],
        artifact_refs: ["11111111-1111-4111-8111-111111111111"]
      )
      expect(stub).to have_been_requested
    end

    it "omits optional fields when not provided" do
      stub = stub_request(:post, "#{base_url}/agent/invoke")
        .to_return(status: 200, body: '{"response":"ok"}', headers: { "Content-Type" => "application/json" })

      client.invoke_agent(agent: "ag", message: "hi")
      expect(a_request(:post, "#{base_url}/agent/invoke").with { |req|
        body = JSON.parse(req.body)
        %w[thread_id user metadata messages attachments].none? { |k| body.key?(k) }
      }).to have_been_made
    end
  end

  # ── Hive Agent ────────────────────────────────────────────────────────────────

  describe "HA1+HA2: invoke_hive_agent endpoint and parsed JSON" do
    it "POSTs to /hive-agent/invoke and returns the body" do
      stub = stub_request(:post, "#{base_url}/hive-agent/invoke")
        .to_return(status: 202, body: '{"run_id":"run_1","request_id":"req_1","status":"pending","webhook_secret":"whsec_x"}', headers: { "Content-Type" => "application/json" })

      result = client.invoke_hive_agent(hive_agent: "agt_1", objective: "Research competitors", callback_url: "https://example.com/cb")
      expect(stub).to have_been_requested
      expect(result).to include("run_id" => "run_1", "webhook_secret" => "whsec_x")
    end
  end

  describe "HA3: async block and required callback_url" do
    it "builds async.enabled true and callback_url; missing callback_url raises" do
      stub = stub_request(:post, "#{base_url}/hive-agent/invoke")
        .with(body: hash_including("async" => { "enabled" => true, "callback_url" => "https://example.com/cb" }))
        .to_return(status: 202, body: '{"status":"pending"}', headers: { "Content-Type" => "application/json" })

      client.invoke_hive_agent(hive_agent: "agt_1", objective: "Research competitors", callback_url: "https://example.com/cb")
      expect(stub).to have_been_requested

      expect {
        client.invoke_hive_agent(hive_agent: "agt_1", objective: "Research competitors", callback_url: "")
      }.to raise_error(ArgumentError, /callback_url is required/)
    end
  end

  describe "HA4: optional sources and metadata" do
    it "includes sources and metadata only when provided" do
      stub = stub_request(:post, "#{base_url}/hive-agent/invoke")
        .to_return(status: 202, body: '{"status":"pending"}', headers: { "Content-Type" => "application/json" })

      client.invoke_hive_agent(hive_agent: "agt_1", objective: "Research competitors", callback_url: "https://example.com/cb")
      expect(a_request(:post, "#{base_url}/hive-agent/invoke").with { |req|
        body = JSON.parse(req.body)
        !body.key?("sources") && !body.key?("metadata")
      }).to have_been_made
    end

    it "includes sources and metadata when provided" do
      stub = stub_request(:post, "#{base_url}/hive-agent/invoke")
        .with(body: hash_including(
          "sources" => { "website_urls" => ["https://example.com"] },
          "metadata" => { "customer_id" => "cus_123" }
        ))
        .to_return(status: 202, body: '{"status":"pending"}', headers: { "Content-Type" => "application/json" })

      client.invoke_hive_agent(
        hive_agent: "agt_1",
        objective: "Research competitors",
        callback_url: "https://example.com/cb",
        sources: { website_urls: ["https://example.com"] },
        metadata: { customer_id: "cus_123" }
      )
      expect(stub).to have_been_requested
    end
  end

  describe "KB1: knowledge base helpers" do
    it "lists and creates knowledge bases on the public paths" do
      stub_request(:get, "#{base_url}/public/workspaces/ws_1/knowledge_bases")
        .to_return(status: 200, body: '{"knowledge_bases":[]}', headers: { "Content-Type" => "application/json" })
      stub_request(:post, "#{base_url}/public/workspaces/ws_1/knowledge_bases")
        .to_return(status: 200, body: '{"knowledge_base":{"id":"kb_1"}}', headers: { "Content-Type" => "application/json" })

      client.list_knowledge_bases(workspace_id: "ws_1")
      client.create_knowledge_base(workspace_id: "ws_1", knowledge_base: { name: "KB" })
      expect(a_request(:get, "#{base_url}/public/workspaces/ws_1/knowledge_bases")).to have_been_made
      expect(a_request(:post, "#{base_url}/public/workspaces/ws_1/knowledge_bases")).to have_been_made
    end
  end

  describe "KBI1: knowledge base item helpers" do
    it "lists items and regenerates on the public paths" do
      stub_request(:get, "#{base_url}/public/workspaces/ws_1/knowledge_bases/kb_1/items")
        .to_return(status: 200, body: '{"knowledge_base_items":[]}', headers: { "Content-Type" => "application/json" })
      stub_request(:post, "#{base_url}/public/workspaces/ws_1/knowledge_bases/kb_1/items/item_1/regenerate")
        .to_return(status: 200, body: '{"request_id":"req_1"}', headers: { "Content-Type" => "application/json" })

      client.list_knowledge_base_items(workspace_id: "ws_1", knowledge_base_id: "kb_1")
      client.regenerate_knowledge_base_item(workspace_id: "ws_1", knowledge_base_id: "kb_1", id: "item_1")
      expect(a_request(:post, "#{base_url}/public/workspaces/ws_1/knowledge_bases/kb_1/items/item_1/regenerate")).to have_been_made
    end
  end

  describe "PA1: public agent helpers" do
    it "lists agents on the public path" do
      stub_request(:get, "#{base_url}/public/workspaces/ws_1/agents")
        .to_return(status: 200, body: '{"agents":[]}', headers: { "Content-Type" => "application/json" })

      client.list_agents(workspace_id: "ws_1")
      expect(a_request(:get, "#{base_url}/public/workspaces/ws_1/agents")).to have_been_made
    end
  end

  describe "PAC1: agent chat helpers" do
    it "creates a chat and clears messages" do
      stub_request(:post, "#{base_url}/public/workspaces/ws_1/agents/agt_1/chats")
        .to_return(status: 200, body: '{"chat":{"id":"c1"}}', headers: { "Content-Type" => "application/json" })
      stub_request(:patch, "#{base_url}/public/workspaces/ws_1/agents/agt_1/chats/cht_1/clear_messages")
        .to_return(status: 200, body: '{"message":"cleared"}', headers: { "Content-Type" => "application/json" })

      client.create_agent_chat(workspace_id: "ws_1", agent_id: "agt_1", chat: { name: "Chat" })
      client.clear_agent_chat_messages(workspace_id: "ws_1", agent_id: "agt_1", chat_id: "cht_1")
      expect(a_request(:patch, "#{base_url}/public/workspaces/ws_1/agents/agt_1/chats/cht_1/clear_messages")).to have_been_made
    end
  end

  describe "R1: get_request" do
    it "GETs /public/requests/:id" do
      stub_request(:get, "#{base_url}/public/requests/req_1")
        .to_return(status: 200, body: '{"request":{"id":"req_1"}}', headers: { "Content-Type" => "application/json" })

      result = client.get_request(id: "req_1")
      expect(result).to eq("request" => { "id" => "req_1" })
    end
  end

  # ── Streaming ─────────────────────────────────────────────────────────────────

  let(:sse_body) do
    "data: {\"type\":\"response\",\"response\":\"Hello\"}\n" \
    "data: {\"type\":\"usage\",\"request_id\":\"r1\",\"stop_reason\":\"completed\"}\n" \
    "data: [DONE]\n"
  end

  # S1 — invoke_prompt_stream sends streaming: true and yields parsed events
  describe "S1: invoke_prompt_stream" do
    it "sends streaming: true and yields parsed SSE events" do
      stub_request(:post, "#{base_url}/prompt/invoke")
        .with(body: hash_including("streaming" => true, "metadata" => { "plan" => "enterprise" }))
        .to_return(status: 200, body: sse_body, headers: { "Content-Type" => "text/event-stream" })

      events = []
      client.invoke_prompt_stream(deployment: "dep", metadata: { plan: "enterprise" }) { |e| events << e }
      expect(events.map { |e| e["type"] }).to eq(%w[response usage])
    end
  end

  # S2 — invoke_agent_stream sends streaming: true and yields parsed events
  describe "S2: invoke_agent_stream" do
    it "sends streaming: true and yields parsed SSE events" do
      stub_request(:post, "#{base_url}/agent/invoke")
        .with(body: hash_including("streaming" => true, "metadata" => { "plan" => "enterprise" }))
        .to_return(status: 200, body: sse_body, headers: { "Content-Type" => "text/event-stream" })

      events = []
      client.invoke_agent_stream(agent: "ag", message: "hi", metadata: { plan: "enterprise" }) { |e| events << e }
      expect(events.map { |e| e["type"] }).to eq(%w[response usage])
    end
  end

  # ── Errors ────────────────────────────────────────────────────────────────────

  # E1 — Non-2xx on non-streaming endpoint raises with status code
  describe "E1: non-2xx on non-streaming endpoint" do
    it "raises with the status code in the message" do
      stub_request(:post, "#{base_url}/prompt/invoke")
        .to_return(status: 422, body: '{"error":"invalid"}', headers: { "Content-Type" => "application/json" })

      expect { client.invoke_prompt(deployment: "dep") }
        .to raise_error(RuntimeError, /422/)
    end
  end

  # E2 — Non-2xx on streaming endpoint raises before any events
  describe "E2: non-2xx on streaming endpoint raises before events" do
    it "raises and yields no events" do
      stub_request(:post, "#{base_url}/agent/invoke")
        .to_return(status: 401, body: "Unauthorized", headers: { "Content-Type" => "text/plain" })

      events = []
      expect do
        client.invoke_agent_stream(agent: "ag", message: "hi") { |e| events << e }
      end.to raise_error(RuntimeError, /401/)
      expect(events).to be_empty
    end
  end

  private

  def with_env(vars)
    old = vars.keys.each_with_object({}) { |k, acc| acc[k.to_s] = ENV[k.to_s] }
    vars.each { |k, v| v.nil? ? ENV.delete(k.to_s) : ENV[k.to_s] = v }
    yield
  ensure
    old.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
  end
end

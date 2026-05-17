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
      ClimateControl.modify "FETCH_HIVE_API_KEY" => nil do
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
      stub_request(:post, "#{base_url}/invoke")
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
      stub = stub_request(:post, "https://custom.example.com/v1/invoke")
        .to_return(status: 200, body: '{"response":"custom"}', headers: { "Content-Type" => "application/json" })

      c = described_class.new(api_key: api_key, base_url: "https://custom.example.com/v1")
      c.invoke_prompt(deployment: "dep")
      expect(stub).to have_been_requested
    end
  end

  # C4 — Trailing slash on base_url is stripped
  describe "C4: trailing slash stripped from base_url" do
    it "does not produce double slashes in the request path" do
      stub = stub_request(:post, "https://api.fetchhive.com/v1/invoke")
        .to_return(status: 200, body: '{"response":"ok"}', headers: { "Content-Type" => "application/json" })

      c = described_class.new(api_key: api_key, base_url: "https://api.fetchhive.com/v1/")
      c.invoke_prompt(deployment: "dep")
      expect(stub).to have_been_requested
    end
  end

  # C5 — Default base URL
  describe "C5: default base URL" do
    it "uses https://api.fetchhive.com/v1 by default" do
      stub = stub_request(:post, "#{base_url}/invoke")
        .to_return(status: 200, body: '{"response":"ok"}', headers: { "Content-Type" => "application/json" })

      client.invoke_prompt(deployment: "dep")
      expect(stub).to have_been_requested
    end
  end

  # ── Auth ─────────────────────────────────────────────────────────────────────

  # A1 — Authorization header sent on every request
  describe "A1: Authorization header" do
    it "sends Authorization: Bearer <key> on every request" do
      stub_request(:post, "#{base_url}/invoke")
        .with(headers: { "Authorization" => "Bearer #{api_key}" })
        .to_return(status: 200, body: '{"response":"ok"}', headers: { "Content-Type" => "application/json" })

      expect { client.invoke_prompt(deployment: "dep") }.not_to raise_error
    end
  end

  # A2 — Content-Type header sent
  describe "A2: Content-Type header" do
    it "sends Content-Type: application/json" do
      stub_request(:post, "#{base_url}/invoke")
        .with(headers: { "Content-Type" => "application/json" })
        .to_return(status: 200, body: '{"response":"ok"}', headers: { "Content-Type" => "application/json" })

      expect { client.invoke_prompt(deployment: "dep") }.not_to raise_error
    end
  end

  # ── Prompt ────────────────────────────────────────────────────────────────────

  # P1 — invoke_prompt POSTs to /invoke
  describe "P1: invoke_prompt endpoint" do
    it "POSTs to /invoke" do
      stub = stub_request(:post, "#{base_url}/invoke")
        .to_return(status: 200, body: '{"response":"ok"}', headers: { "Content-Type" => "application/json" })

      client.invoke_prompt(deployment: "dep")
      expect(stub).to have_been_requested
    end
  end

  # P2 — invoke_prompt returns parsed JSON body
  describe "P2: invoke_prompt returns parsed JSON" do
    it "returns a Hash with the response body" do
      stub_request(:post, "#{base_url}/invoke")
        .to_return(status: 200, body: '{"response":"Hello","request_id":"r1"}', headers: { "Content-Type" => "application/json" })

      result = client.invoke_prompt(deployment: "dep")
      expect(result).to eq("response" => "Hello", "request_id" => "r1")
    end
  end

  # P3 — streaming: false injected; optional fields only when provided
  describe "P3: invoke_prompt body shape" do
    it "injects streaming: false and omits absent optional fields" do
      stub = stub_request(:post, "#{base_url}/invoke")
        .with(body: hash_including("deployment" => "dep", "streaming" => false))
        .to_return(status: 200, body: "{}", headers: { "Content-Type" => "application/json" })

      client.invoke_prompt(deployment: "dep")
      expect(stub).to have_been_requested
    end

    it "includes variant, inputs, and user when provided" do
      stub = stub_request(:post, "#{base_url}/invoke")
        .with(body: hash_including("variant" => "v2", "inputs" => { "k" => "v" }, "user" => "u1"))
        .to_return(status: 200, body: "{}", headers: { "Content-Type" => "application/json" })

      client.invoke_prompt(deployment: "dep", variant: "v2", inputs: { k: "v" }, user: "u1")
      expect(stub).to have_been_requested
    end

    it "omits variant, inputs, and user when not provided" do
      stub = stub_request(:post, "#{base_url}/invoke")
        .to_return(status: 200, body: "{}", headers: { "Content-Type" => "application/json" })

      client.invoke_prompt(deployment: "dep")
      body = JSON.parse(stub.with.body)
      expect(body).not_to have_key("variant")
      expect(body).not_to have_key("inputs")
      expect(body).not_to have_key("user")
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
      body = JSON.parse(stub.with.body)
      expect(body).not_to have_key("async")
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
    it "includes thread_id, user, messages, image_urls when provided" do
      stub = stub_request(:post, "#{base_url}/agent/invoke")
        .with(body: hash_including(
          "thread_id"  => "t1",
          "user"       => "u1",
          "messages"   => [{ "role" => "user", "content" => "hi" }],
          "image_urls" => ["https://img.example.com/a.png"]
        ))
        .to_return(status: 200, body: '{"response":"ok"}', headers: { "Content-Type" => "application/json" })

      client.invoke_agent(
        agent: "ag", message: "hi",
        thread_id: "t1", user: "u1",
        messages: [{ role: "user", content: "hi" }],
        image_urls: ["https://img.example.com/a.png"]
      )
      expect(stub).to have_been_requested
    end

    it "omits optional fields when not provided" do
      stub = stub_request(:post, "#{base_url}/agent/invoke")
        .to_return(status: 200, body: '{"response":"ok"}', headers: { "Content-Type" => "application/json" })

      client.invoke_agent(agent: "ag", message: "hi")
      body = JSON.parse(stub.with.body)
      expect(body).not_to have_key("thread_id")
      expect(body).not_to have_key("user")
      expect(body).not_to have_key("messages")
      expect(body).not_to have_key("image_urls")
    end
  end

  # ── Streaming ─────────────────────────────────────────────────────────────────

  let(:sse_body) do
    "data: {\"type\":\"delta\",\"content\":\"Hello\"}\n" \
    "data: {\"type\":\"done\",\"request_id\":\"r1\"}\n" \
    "data: [DONE]\n"
  end

  # S1 — invoke_prompt_stream sends streaming: true and yields parsed events
  describe "S1: invoke_prompt_stream" do
    it "sends streaming: true and yields parsed SSE events" do
      stub_request(:post, "#{base_url}/invoke")
        .with(body: hash_including("streaming" => true))
        .to_return(status: 200, body: sse_body, headers: { "Content-Type" => "text/event-stream" })

      events = []
      client.invoke_prompt_stream(deployment: "dep") { |e| events << e }
      expect(events.map { |e| e["type"] }).to eq(%w[delta done])
    end
  end

  # S2 — invoke_agent_stream sends streaming: true and yields parsed events
  describe "S2: invoke_agent_stream" do
    it "sends streaming: true and yields parsed SSE events" do
      stub_request(:post, "#{base_url}/agent/invoke")
        .with(body: hash_including("streaming" => true))
        .to_return(status: 200, body: sse_body, headers: { "Content-Type" => "text/event-stream" })

      events = []
      client.invoke_agent_stream(agent: "ag", message: "hi") { |e| events << e }
      expect(events.map { |e| e["type"] }).to eq(%w[delta done])
    end
  end

  # ── Errors ────────────────────────────────────────────────────────────────────

  # E1 — Non-2xx on non-streaming endpoint raises with status code
  describe "E1: non-2xx on non-streaming endpoint" do
    it "raises with the status code in the message" do
      stub_request(:post, "#{base_url}/invoke")
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
    old = vars.transform_values { |_| ENV[_] }
    vars.each { |k, v| v.nil? ? ENV.delete(k.to_s) : ENV[k.to_s] = v }
    yield
  ensure
    old.each { |k, v| v.nil? ? ENV.delete(k.to_s) : ENV[k.to_s] = v }
  end
end

# frozen_string_literal: true

require "spec_helper"
require "fetch_hive/streaming"
require "stringio"

RSpec.describe FetchHive::Streaming do
  def parse(str)
    events = []
    described_class.parse_sse(StringIO.new(str)) { |e| events << e }
    events
  end

  # SSE1 — Parses a clean single-chunk stream into one event per data: line
  describe "SSE1: clean stream" do
    it "yields one event per data: line" do
      body = "data: {\"type\":\"response\",\"response\":\"Hi\"}\n" \
             "data: {\"type\":\"usage\",\"request_id\":\"r1\",\"stop_reason\":\"completed\"}\n" \
             "data: [DONE]\n"

      events = parse(body)
      expect(events.length).to eq(2)
      expect(events[0]).to eq("type" => "response", "response" => "Hi")
      expect(events[1]).to eq("type" => "usage", "request_id" => "r1", "stop_reason" => "completed")
    end
  end

  # SSE2 — Reassembles events from chunks split mid-line
  describe "SSE2: split-chunk reassembly" do
    it "reconstructs events split across multiple reads" do
      # Simulate a stream whose content is split mid-line
      chunk1 = "data: {\"type\":\"res"
      chunk2 = "ponse\",\"response\":\"A\"}\n"
      chunk3 = "data: [DONE]\n"

      combined = StringIO.new(chunk1 + chunk2 + chunk3)
      events = []
      described_class.parse_sse(combined) { |e| events << e }

      expect(events.length).to eq(1)
      expect(events[0]).to eq("type" => "response", "response" => "A")
    end

    it "handles newlines split across chunks" do
      # Body with the newline separator at the boundary
      body1 = "data: {\"type\":\"response\"}"
      body2 = "\ndata: [DONE]\n"
      events = []
      described_class.parse_sse(StringIO.new(body1 + body2)) { |e| events << e }
      expect(events.length).to eq(1)
    end
  end

  # SSE3 — Skips non-data lines (comments, blank, event:, id:)
  describe "SSE3: non-data lines skipped" do
    it "ignores comment, blank, event, and id lines" do
      body = ": this is a comment\n" \
             "\n" \
             "event: message\n" \
             "id: 42\n" \
             "data: {\"type\":\"response\",\"response\":\"X\"}\n" \
             "data: [DONE]\n"

      events = parse(body)
      expect(events.length).to eq(1)
      expect(events[0]["response"]).to eq("X")
    end
  end

  # SSE4 — Skips malformed JSON silently
  describe "SSE4: malformed JSON skipped" do
    it "silently skips lines with invalid JSON and continues" do
      body = "data: {broken json\n" \
             "data: {\"type\":\"response\"}\n" \
             "data: [DONE]\n"

      events = []
      expect { events = parse(body) }.not_to raise_error
      expect(events.length).to eq(1)
      expect(events[0]["type"]).to eq("response")
    end
  end

  # SSE5 — Stops at [DONE]
  describe "SSE5: stops at [DONE]" do
    it "stops yielding events after data: [DONE]" do
      body = "data: {\"type\":\"response\"}\n" \
             "data: [DONE]\n" \
             "data: {\"type\":\"should_not_appear\"}\n"

      events = parse(body)
      expect(events.length).to eq(1)
      expect(events[0]["type"]).to eq("response")
    end

    it "handles [DONE] with surrounding whitespace" do
      body = "data: [DONE]  \n"
      events = parse(body)
      expect(events).to be_empty
    end
  end
end

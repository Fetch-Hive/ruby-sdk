# frozen_string_literal: true

require "fetch_hive"

client = FetchHive::Client.new(api_key: ENV.fetch("FETCH_HIVE_API_KEY"))

client.invoke_agent_stream(
  agent: "my-agent",
  message: "Tell me a short story about a robot learning Ruby"
) do |chunk|
  case chunk["type"]
  when "delta"
    print chunk["content"]
    $stdout.flush
  when "done"
    puts "\n\n[Done — request_id: #{chunk['request_id']}]"
  end
end

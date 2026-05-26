# frozen_string_literal: true

require "fetch_hive"

client = FetchHive::Client.new(api_key: ENV.fetch("FETCH_HIVE_API_KEY"))

result = client.invoke_prompt(
  deployment: "my-prompt",
  inputs: { name: "Alice", topic: "Ruby" },
  metadata: {}
)

puts result["response"]

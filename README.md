# Fetch Hive Ruby SDK

Official Ruby SDK for the [Fetch Hive](https://fetchhive.com) API — invoke prompts, workflows, and agents with a clean, idiomatic interface.

**Version:** 0.1.9

## Installation

Add to your `Gemfile`:

```ruby
gem "fetch_hive", "~> 0.1.9"
```

Then run:

```bash
bundle install
```

Or install directly:

```bash
gem install fetch_hive
```

## Quick start

```ruby
require "fetch_hive"

client = FetchHive::Client.new(api_key: ENV["FETCH_HIVE_API_KEY"])

# Invoke a prompt
result = client.invoke_prompt(deployment: "my-prompt", inputs: { name: "Alice" })
puts result["response"]

# Invoke a workflow
run = client.invoke_workflow(deployment: "my-workflow", inputs: { topic: "AI" })
puts run["output"]

# Send a message to an agent (non-streaming)
reply = client.invoke_agent(agent: "my-agent", message: "Hello!")
puts reply["response"]

# Stream an agent response
client.invoke_agent_stream(agent: "my-agent", message: "Tell me a story") do |chunk|
  print chunk["content"] if chunk["type"] == "delta"
end
```

## Configuration

| Option | Default | Description |
|---|---|---|
| `api_key` | `ENV["FETCH_HIVE_API_KEY"]` | Bearer token from the Fetch Hive dashboard |
| `base_url` | `https://api.fetchhive.com/v1` | Override the API base URL |
| `timeout` | `120` | Request timeout in seconds |

## Links

- [Fetch Hive dashboard](https://app.fetchhive.com)
- [API documentation](https://docs.fetchhive.com)
- [GitHub](https://github.com/Fetch-Hive/ruby-sdk)

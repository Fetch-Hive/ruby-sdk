# fetch_hive

Official Ruby SDK for [Fetch Hive](https://fetchhive.com) — invoke AI prompts, workflows, and agents from your application.

[![Gem Version](https://badge.fury.io/rb/fetch_hive.svg)](https://rubygems.org/gems/fetch_hive)

## Installation

Add to your `Gemfile`:

```ruby
gem "fetch_hive", "~> 0.2.4"
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
```

Get your API key from the [Fetch Hive dashboard](https://app.fetchhive.com).

## Invoke a prompt

```ruby
result = client.invoke_prompt(
  deployment: "my-prompt",
  inputs: { name: "Alice", topic: "machine learning" }
)
puts result["response"]
```

## Invoke a prompt (streaming)

```ruby
client.invoke_prompt_stream(deployment: "my-prompt", inputs: { name: "Alice" }) do |chunk|
  case chunk["type"]
  when "response" then print chunk["response"]
  when "usage"    then puts "\nUsage: #{chunk['usage']}"
  end
end
```

## Invoke a workflow

```ruby
run = client.invoke_workflow(
  deployment: "my-workflow",
  inputs: { customer_id: "42" }
)
puts run["status"], run["output"]
```

## Invoke a workflow (async)

```ruby
run = client.invoke_workflow(
  deployment: "my-workflow",
  inputs: { customer_id: "42" },
  async_mode: true,
  callback_url: "https://example.com/webhook"
)
puts "Queued: #{run['run_id']}"
```

## Invoke an agent

```ruby
reply = client.invoke_agent(
  agent: "my-agent",
  message: "What is the weather in London?"
)
puts reply["response"]
```

## Invoke an agent (streaming)

```ruby
client.invoke_agent_stream(
  agent: "my-agent",
  message: "What is the weather in London?",
  thread_id: "session-abc123"  # optional — persist conversation history
) do |chunk|
  case chunk["type"]
  when "response" then print chunk["response"]
  when "tool"     then puts "\nCalling tool: #{chunk['tool']}"
  when "usage"    then puts "\nUsage: #{chunk['usage']}"
  end
end
```

## Multimodal (image) inputs

```ruby
result = client.invoke_agent(
  agent: "vision-agent",
  message: "Describe this image",
  image_urls: ["https://example.com/photo.jpg"]
)
puts result["response"]
```

## Authentication

Pass the API key to the constructor or set the environment variable:

```bash
export FETCH_HIVE_API_KEY=fhk_...
```

```ruby
client = FetchHive::Client.new  # picks up FETCH_HIVE_API_KEY automatically
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

## Version

0.2.4

## License

MIT — see [LICENSE](LICENSE).

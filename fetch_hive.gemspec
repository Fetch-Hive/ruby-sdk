Gem::Specification.new do |spec|
  spec.name          = "fetch_hive"
  spec.version       = "0.1.8"
  spec.authors       = ["Fetch Hive"]
  spec.email         = ["tom@fetchhive.com"]
  spec.summary       = "Official Ruby SDK for the Fetch Hive API"
  spec.description   = "Invoke prompts, workflows, and agents on the Fetch Hive platform from Ruby."
  spec.homepage      = "https://fetchhive.com"
  spec.license       = "MIT"

  spec.required_ruby_version = ">= 3.1"

  spec.metadata["homepage_uri"]    = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/Fetch-Hive/ruby-sdk"
  spec.metadata["documentation_uri"] = "https://docs.fetchhive.com"

  spec.files = Dir["lib/**/*.rb", "README.md", "LICENSE"]
  spec.require_paths = ["lib"]

  spec.add_dependency "faraday", "~> 2.0"
  spec.add_dependency "faraday-net_http", "~> 3.0"
end

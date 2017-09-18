# coding: utf-8
lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "whirlpool/version"

Gem::Specification.new do |spec|
  spec.name          = "whirlpool"
  spec.version       = Whirlpool::VERSION
  spec.authors       = ["Simon Worthington"]
  spec.email         = ["simon.worthington@digital.cabinet-office.gov.uk"]

  spec.summary       = %q{Question and answer engine built upon the AQuAE spec.}
  spec.description   = <<-HEREDOC
    This gem is an application that can ask and answer questions as part of an
    AQuAE (Attributes, Questions, Answers and Elibility) system. It provides both
    a simple client interface for integration into other applications (such as web
    servers) and a standalone application that can act as an intermediate server
    or data provider in a federation.
    HEREDOC
  spec.homepage      = "https://www.github.com/alphagov/whirlpool"

  # Prevent pushing this gem to RubyGems.org. To allow pushes either set the 'allowed_push_host'
  # to allow pushing to a single host or delete this section to allow pushing to any host.
  #if spec.respond_to?(:metadata)
  #  spec.metadata["allowed_push_host"] = "TODO: Set to 'http://mygemserver.com'"
  #else
  #  raise "RubyGems 2.0 or newer is required to protect against " \
  #    "public gem pushes."
  #end

  spec.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|tasks)/})
  end
  spec.bindir        = 'bin'
  spec.executables   = spec.files.grep(%r{^#{spec.bindir}/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency 'aquae'
  spec.add_dependency 'concurrent-ruby'
  spec.add_development_dependency "bundler", "~> 1.15"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "test-unit", "~> 3.2.3"
end

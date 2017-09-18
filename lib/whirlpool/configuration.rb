require 'yaml'
require 'aquae/federation'
require 'aquae/protos/metadata.pb'
require_relative 'query_loader'

module Whirlpool
  class Configuration
    def initialize config_file
      config = YAML.load_file(config_file).to_h
      @federation = Aquae::Federation.new Aquae::Metadata::Federation.decode File.binread config['metadata']
      @key = File.binread config['keyfile']
      @this_node = @federation.node config['this_node']
      @query_blocks = Whirlpool::QueryLoader.load *(config['queryfiles'] || [])
    end

    # The federation parsed from metadata.
    attr_reader :federation

    # A Node object representing this node in the metadata.
    attr_reader :this_node

    # The private key for this node.
    attr_reader :key

    # Ruby blocks that implement local queries.
    attr_reader :query_blocks
  end
end
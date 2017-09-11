require 'aquae/protos/messaging.pb'

module Viaduct
  # Question someone else can answer
  class RemoteQuestion
    include Aquae::Messaging
    
    attr_reader :name

    def initialize name, endpoint, node_id, query_id
      @name = name
      @endpoint = endpoint
      @node_id = node_id
      @query_id = query_id
    end

    # Sends SecondWhistle and waits for response
    def answer
      puts "Answering #{name}..."
      @socket ||= @endpoint.connect_to @node_id
      @socket.write SecondWhistle.new queryId: @query_id
      @socket.read
    end
  end
end
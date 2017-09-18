require 'aquae/protos/messaging.pb'

module Whirlpool
  # Question someone else can answer
  class RemoteQuestion
    include Aquae::Messaging
    
    attr_reader :name

    def initialize name, socket, node_id, query_id
      @name = name
      @socket = socket
      @query_id = query_id
    end

    # Sends SecondWhistle and waits for response
    def answer
      puts "Answering #{name}..."
      @socket.write SecondWhistle.new queryId: @query_id
      @socket.read
    end
  end
end
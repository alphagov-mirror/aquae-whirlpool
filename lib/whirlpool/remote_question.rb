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
      answer = @socket.read
      unless answer.is_a? QueryAnswer
        raise Whirlpool::StateError, "Bad message received: expected #{QueryAnswer}, received #{answer.inspect}"
      end
      unless answer.queryId == @query_id
        raise Whirlpool::StateError, "Response received with incorrect query ID: expected #{@query_id}, received #{answer.queryId}"
      end
      answer.value || answer.error
    end
  end
end
require 'aquae/protos/messaging.pb'

module Viaduct
  # A match that will happen on a different node.
  class RemoteMatch
    include Aquae::Messaging

    def initialize question, endpoint, node_id, query_id
      @question_name = question
      @endpoint = endpoint
      @node_id = node_id
      @query_id = query_id
    end

    # Prepares the remote server to answer the question.
    # May be called multiple times.
    def match scope
      # Pass-thru signed identity
      @socket ||= @endpoint.connect_to @node_id
      @socket.write SignedQuery.new(
        question: Question.new(name: @question.name), #TODO: dsaId
        queryId: @query_id,
        scope: scope)

      # Wait for the response
      @socket.read
    end

    # Sends Finish
    def finish
      @socket ||= @endpoint.connect_to @node_id
      @socket.write Finish.new queryId: @query_id
      @socket.close
    end
  end
end
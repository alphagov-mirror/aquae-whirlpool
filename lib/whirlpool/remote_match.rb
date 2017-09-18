require 'aquae/protos/messaging.pb'

module Whirlpool
  # A match that will happen on a different node.
  class RemoteMatch
    include Aquae::Messaging

    def initialize question, socket, node_id, matching_impls, query_id
      @question_name = question
      @socket = socket
      @impls = matching_impls
      @query_id = query_id
    end

    # Prepares the remote server to answer the question.
    # May be called multiple times.
    def match scope
      # Pass-thru signed identity
      @socket.write SignedQuery.new(
        query: Query.new(
          question: Question.new(name: @question_name.to_s), #TODO: dsaId
          queryId: @query_id,
          scope: scope))

      # Wait for the response
      @socket.read
    end

    # Sends Finish
    def finish
      @socket.write Finish.new queryId: @query_id
      @socket.close
    end
  end
end
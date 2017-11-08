require 'aquae/protos/messaging.pb'

module Whirlpool
  class RemoteClient
    include Aquae::Messaging

    def initialize federation, socket
      @federation = federation
      @socket = socket
    end

    def question_name
      query.question.name
    end

    def query_id
      query.queryId
    end

    # In fact, we have already received the choice
    # and now we will just verify that the one we received
    # is one of the possibles we generated.
    def choices= value
      @choice = value.detect {|c| plan_matches? c, received_plan } #TODO
      if @choice.nil?
        bad_query BadQueryResponse::Reason::CANNOT_ANSWER_QUERY
      end
    end

    # Return the plan that matched the remote request
    # as found when we called choices=
    def choice
      @choice
    end

    def signed_scope
      query.scope
    end

    # @param value [MatchCompleteResponse, MoreIdentityResponse] Describes the
    #     results of the matching round.
    def match_response= value
      response = QueryResponse.new queryId: query_id
      case value
      when MatchCompleteResponse
        response.match_complete_response = value
      when MoreIdentityResponse
        # TODO: other class needs to generate missing fields
        response.more_identity_response = value
        # Kill the query so that we wait for a new one
        @query = nil
      end
      @socket.write response
    end

    # Blocks until we have received a SecondWhistle
    def ready_to_ask
      whistle = @socket.read
      # TODO: what happens if we receive new identity data?
      case whistle
      when SecondWhistle
        true
      when SignedQuery
        self.signed_query = value
        false
      else
        unexpected_message query, SecondWhistle, SignedQuery
      end
    end

    def answer= value
      response = QueryAnswer.new queryId: query_id
      case value
      when ValueResponse
        response.value = value
      when ErrorResponse
        response.error = value
      end

      @socket.write response
      @socket.close
    end

    def cancel exception
      die MessagingError.new reason: "Server error: #{exception.message}"
      raise exception
    end

    private
    def signed_query
      @query || begin
        query = @socket.read
        assert_message_type SignedQuery, query
        self.signed_query = query
      end
    end

    def signed_query= value
      if @query.nil?
        # TODO: check sig is valid
      else
        # TODO: check sig matches previous sig and is valid
      end
      @query = value
    end

    def query
      signed_query.query
    end

    def plan_matches? graph, plan
      plan_as_graph = plan_to_graph plan
      plan_as_graph.to_plans(graph.root_query).detect {|f| f == graph }
    end

    def plan_to_graph plan
      plans = plan.required_query.map &method(:plan_to_graph)
      graph = Aquae::QueryGraph.new *plans
      query_spec = @federation.query plan.query.name
      graph.add_query query_spec
      query_spec.choices.each &graph.method(:add_choice)
      graph
    end

    def received_plan
      signed_scope.scope.plan
    end

    def assert_message_type type, instance
      unless instance.is_a? type
        unexpected_message instance, type
      end
    end

    def bad_query reason
      die BadQueryResponse.new queryId: query_id, reason: reason
      raise Whirlpool::BadQuery, reason
    end

    def unexpected_message received, *expecting
      reason = "Expecting #{expecting.join(' | ')}, received #{received.inspect}"
      die MessagingError.new reason: reason
      raise Whirlpool::StateError, reason
    end

    # Write a response onto the socket and close the connection.
    def die response
      @socket.write response
      @socket.close
    end
  end
end
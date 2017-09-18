require 'aquae/endpoint'
require 'aquae/protos/metadata.pb'
require 'aquae/protos/messaging.pb'
require 'aquae/query_graph'
require 'aquae/query_spec'
require 'aquae/endpoint'
require_relative 'query_plan'
require_relative 'running_query'

module Whirlpool
  StateError = Class.new StandardError

  class Application
    include Aquae::Messaging

    def initialize config
      @federation = config.federation
      @this_node = config.this_node
      @questions = Aquae::QueryGraph.populate *@federation.queries
      @questions.freeze
      @endpoint = Aquae::Endpoint.new @federation, config.key, @this_node
      @blocks = config.query_blocks
    end

    # Start running the Whirlpool application on this thread
    def start!
      @endpoint = Aquae::Endpoint.new @metadata, File.binread(@key_file), @this_node
      STDOUT.puts "Whirlpool running."
      @endpoint.accept_messages do |socket|
        Thread.start { accept_query socket }
      end
    end

    def start_query
      Whirlpool::Client::make_pair do |app|
        Thread.new { start_query! app }
      end
    end

    private 
    def start_query! client
      # Examine available choices for the query.
      query_spec = @federation.query client.question_name.value
      choices = @questions.to_plans query_spec

      # Expose choices to the user
      client.choices = choices
      choice = client.choice.value

      # Calculate required matches
      plan = plan_query choice
      identity = client.identity.take
      scope = get_scope plan, identity
      loop do
        matches = plan.matches.map {|match| match.match scope}
        if matches.any? {|resp| resp.is_a? BadQueryResponse }
          raise "A match thought our query was bad: #{matches.inspect}"
        end
        if matches.map(&:matchCompleteResponse).all? {|resp| resp.is_a? MatchCompleteResponse }
          client.identity_response = []
          break # We are matched
        else
          # TODO: handle more identity responses
        end
      end

      # Now we can submit the question
      answer = plan.question.answer
      unless answer.is_a? QueryAnswer
        raise Whirlpool::StateError, "Bad message received: expected #{QueryAnswer}, received #{answer.inspect}"
      end
      unless answer.queryId == plan.query_id
        raise Whirlpool::StateError, "Response received with incorrect query ID: expected #{plan.query_id}, received #{answer.queryId}"
      end

      if answer.value && answer.value.is_a?(ValueResponse)
        client.answer = true
      elsif answer.error && answer.error.is_a?(ErrorResponse)
        raise "Error executing query #{plan.query_id}: #{answer.error}"
      end
    rescue Exception => e
      client.cancel e
      raise
    ensure
      #TODO: finish messages
    end

    def send_answer result
      puts "RESULT: #{result}"
    end

    def get_scope plan, identity
      p identity, identity.class
      Query::SignedScope.new(
        scope: Query::Scope.new(
          originalQuestion: Question.new(name: plan.question.name),
          nOnce: SecureRandom.hex, 
          subjectIdentity: SignedIdentity.new(
            identity: PersonIdentity.new(identity)),
          choice: [])) # TODO modify for Andy's new things
    end
    
    def plan_query choice
      Whirlpool::QueryPlan.new @blocks, @endpoint, @this_node, choice
    end

    def user_decide choices
      choices.detect {|c| c.all_choices.flat_map(&:required_queries).map(&:name).include? 'pip>8?' }
    end

    def accept_query socket
      matches = []
      query = nil
      loop do
        m = socket.read
        raise Whirlpool::StateError, "Unexpected message type: #{m.class}" unless m.is_a? SignedQuery
        #TODO check signature
        query = m.query

        unless (response = bad_query?(query)).nil?
          socket.write response
          return
        end

        # Try and decrypt identity
        identity = decrypt_identity query.scope.scope.subjectIdentity
        unless identity_has_fields? identity
          socket.write BadQueryResponse.new(reason: BadQueryResponse::Reason::MissingIdentityFields, queryId: m.queryId)
          return # TODO: resume?
        end

        # Matching
        matches = @data.select {|id| potential_match? identity, id }
        break if matches.none? || matches.one?

        # No match
        socket.write QueryResponse.new(
          queryId: query.queryId,
          moreIdentityResponse: MoreIdentityResponse.new #TODO: fields
        )
      end

      # Matching response
      socket.write QueryResponse.new(
        queryId: query.queryId,
        matchCompleteResponse: MatchCompleteResponse.new)

      # Wait for SecondWhistle
      loop until (m = socket.read).is_a? SecondWhistle
      case question
      when "pip>8?"
      when "dla-higher?"
        response = QueryAnswer.new queryId: query.queryId
        if matches.one?
          response.valueResponse = ValueResponse.new
        else
          response.errorResponse = ErrorResponse.new
        end
        socket.write response
      when "bb?"
        simon3 = @endpoint.connect_to 'simon3'
        simon3_query = SignedQuery.new(
          query: Query.new(
            queryId: query.queryId,
            question: Question.new(name: 'pip>8?'),
            scope: query.scope))
        simon3.write simon3_query

        simon4 = @endpoint.connect_to 'simon4'
        simon4_query = SignedQuery.new(
          query: Query.new(
            queryId: query.queryId,
            question: Question.new(name: 'dla-higher?'),
            scope: query.scope))
        simon4.write simon4_query

        s3_response = simon3.read
        s4_response = simon4.read
      end
    rescue Exception => e
      STDERR.puts e.inspect, e.backtrace.join("\n")
      raise e
    ensure
      socket.close
    end

    def bad_query? m
      reason ||= (BadQueryResponse::Reason::CannotAnswerQuery if m.nil?)
      reason ||= (BadQueryResponse::Reason::CannotAnswerQuery unless m.question.name == "bb?" || m.question.name == "pip>8?" || m.question.name == "dla-higher?")
      reason ||= (BadQueryResponse::Reason::MissingIdentity if m.scope.nil?)
      # TODO: check scope
      reason ||= (BadQueryResponse::Reason::MissingIdentity if m.scope.scope.subjectIdentity.nil?)
      reason ||= (BadQueryResponse::Reason::MissingIdentity unless identity_valid? m.scope.scope.subjectIdentity)
      reason ||= (BadQueryResponse::Reason::MissingIdentityFields unless identity_has_fields? m.scope.scope.subjectIdentity.identity)
      reason ||= (BadQueryResponse::Reason::ServiceUnauthorized if false) #TODO
      reason ||= (BadQueryResponse::Reason::NoConsentToken if false) #TODO
      BadQueryResponse.new(reason: reason, queryId: m.queryId) unless reason.nil?
    end

    def identity_valid? signed_id
      return false if signed_id.nil?
      # TODO: check root hash
      # TODO: check hash signature
      true
    end

    # For a given query, checks that the required identity fields are present.
    # Can be used for both RedactableIdentity or PORO Identity.
    def identity_has_fields? id
      return false if id.nil?
      # TODO: check based on query
      return false if id.surname.nil?
      return false if id.postcode.nil?
      return false if id.birthYear.nil?
      true
    end

    def decrypt_identity signed_id
      decrypted = Identity.new
      decrypted.surname = decrypt_redactable_string signed_id.identity.surname, signed_id.nodeKeys
      decrypted.postcode = decrypt_redactable_string signed_id.identity.postcode, signed_id.nodeKeys
      decrypted.birthYear = decrypt_redactable_string signed_id.identity.birthYear, signed_id.nodeKeys
      decrypted.initials = decrypt_redactable_string signed_id.identity.initials, signed_id.nodeKeys
      decrypted
    end

    def decrypt_redactable_string string, keys
      return if string.nil?
      if !string.value.nil?
        string.value.value
      elsif !string.encrypted.nil?
        key = keys[@this_node]
        # TODO: actually decrypt
        string.encrypted.blob
      end
    end

    def potential_match? a, b
      (a.surname.nil? || a.surname == b.surname) &&
      (a.postcode.nil? || a.postcode == b.postcode) &&
      (a.birthYear.nil? || a.birthYear == b.birthYear) &&
      (a.initials.nil? || a.initials == b.initials)
    end

    def plan_query graph
      Whirlpool::QueryPlan.new @blocks, @endpoint, @this_node, graph
    end
  end
end

if $0 == __FILE__
  raise ArgumentError.new "Should be 3 parameters: metadata_file key_file this_node" unless ARGV.size == 3 or ARGV.size == 4
  data = ARGV.size == 3 ? nil : const_get(ARGV[3])
  app = Whirlpool::Application.new ARGV[0], ARGV[1], ARGV[2], data
  app.start!
end
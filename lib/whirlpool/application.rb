require 'aquae/endpoint'
require 'aquae/protos/metadata.pb'
require 'aquae/protos/messaging.pb'
require 'aquae/query_graph'
require 'aquae/query_spec'
require 'aquae/endpoint'
require 'logger'
require_relative 'query_plan'
require_relative 'local_client'
require_relative 'remote_client'

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
      @logger = Logger.new STDOUT
    end

    # Start running the Whirlpool application on this thread
    def start!
      STDOUT.puts "Whirlpool running."
      @endpoint.accept_messages do |socket|
        @logger.info { "Started responding to new query from #{socket.node.name}" }
        Thread.start { start_query! RemoteClient.new(@federation, socket) }
      end
    end

    def start_query
      Whirlpool::Client::make_pair do |app|
        Thread.start { start_query! app }
      end
    end

    private
    def start_query! client
      # Examine available choices for the query.
      query_spec = @federation.query client.question_name
      @logger.info { "#{client.query_id}: Question chosen as #{client.question_name}" }
      choices = @questions.to_plans query_spec

      # Expose choices to the user
      client.choices = choices
      @logger.debug { "#{client.query_id}: Choice chosen as #{client.choice.inspect}" }
      choice = client.choice
      query_id = client.query_id

      # Formulate execution plan
      plan = plan_query choice, query_id
      @logger.debug { "#{client.query_id}: Question: #{plan.question.inspect}" }
      @logger.debug { "#{client.query_id}: Matches: #{plan.matches.inspect}" }
      # TODO: verification
      loop do
        # We get the signed scope in a different way depending on if we are first asker or not
        # So this must be supplied by the client, either from a consent server or the received query
        scope = client.signed_scope
        @logger.debug { "#{client.query_id}: Matching with identity: #{scope.inspect}"}
        matches = plan.matches.map {|match| match.match scope}
        if matches.any? {|resp| !resp.is_a? QueryResponse }
          raise "A match thought our query was bad: #{matches.inspect}"
        end

        # In order to move on, we need every match to be a confident one.
        # This is highlighted by the presence of a MatchCompleteResponse from everyone.
        if matches.map(&:matchCompleteResponse).all? {|resp| resp.is_a? MatchCompleteResponse }
          @logger.info { "#{client.query_id}: Matching complete!"}
          client.match_response = MatchCompleteResponse.new
          break if client.ready_to_ask
        elsif (mores = matches.map(&:moreIdentityResponse)).all? {|resp| resp.is_a? MoreIdentityResponse}
          # TODO: merging of identity field requests
          # we unpack this only to pack it later?????
          @logger.info { "#{client.query_id}: Matching incomplete."}
          client.match_response = merge_identity_fields mores
        end
      end

      # Now we can submit the question
      answer = plan.question.answer
      @logger.debug { "#{client.query_id}: Answering: #{answer.inspect}" }
      client.answer = answer
      if answer.is_a?(ErrorResponse)
        raise "Error executing query #{plan.query_id}: #{answer.inspect}"
      end
      @logger.info { "#{client.query_id}: Query execution complete... goodbye" }
    rescue Exception => e
      @logger.error { "#{e.message} #{e.backtrace.join("\n\t")}" }
      client.cancel e
      raise
    ensure
      #TODO: finish messages
    end

    def plan_query choice, query_id
      Whirlpool::QueryPlan.new @blocks, @endpoint, @this_node, choice, query_id
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
  end
end

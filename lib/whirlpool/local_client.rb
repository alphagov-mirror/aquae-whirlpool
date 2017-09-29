require 'concurrent'
require 'securerandom'
require 'aquae/protos/messaging.pb'

module Whirlpool
  QueryCancelled = Class.new StandardError

  module Client
    # Makes a pair of classes, one for the client and one for the app,
    # which communicate using shared concurrency variables
    def self.make_pair &app_thread_constructor
      question_name_ivar = Concurrent::IVar.new
      choices_ivar = Concurrent::IVar.new
      choice_ivar = Concurrent::IVar.new
      signed_scope_mvar = Concurrent::MVar.new
      match_response_mvar = Concurrent::MVar.new
      answer_ivar = Concurrent::IVar.new
      app = LocalClient.new question_name_ivar, choices_ivar, choice_ivar, signed_scope_mvar, match_response_mvar, answer_ivar
      thread = yield app
      client = RunningQuery.new thread, question_name_ivar, choices_ivar, choice_ivar, signed_scope_mvar, match_response_mvar, answer_ivar
      client
    end

    class RunningQuery
      def initialize app_thread, question_name_ivar, choices_ivar, choice_ivar, signed_scope_mvar, match_response_mvar, answer_ivar
        @thread = app_thread
        @question_name_ivar = question_name_ivar
        @choices_ivar = choices_ivar
        @choice_ivar = choice_ivar
        @signed_scope_mvar = signed_scope_mvar
        @match_response_mvar = match_response_mvar
        @answer_ivar = answer_ivar
      end

      def question_name= value
        @question_name_ivar.set value
      end

      def choices
        # TODO: readonly?
        @choices_ivar
      end

      def choice= value
        @choice_ivar.set value
      end

      def signed_scope= value
        @signed_scope_mvar.put value
      end

      def match_response
        # TODO: readonly?
        @match_response_mvar
      end

      # Returns the query answer if one was found,
      # or an Exception if there was an error
      def answer
        # TODO: transform. is that a future?
        Concurrent::dataflow(@answer_ivar) {|answer| answer.is_a? Aquae::Messaging::ValueResponse }
      end

      def cancel
        exception = Whirlpool::QueryCancelled.new "User cancelled the query"
        @choice_ivar.fail exception unless @choice_ivar.complete?
        @thread.raise exception
      end
    end

    # TODO names
    class LocalClient
      def initialize question_name_ivar, choices_ivar, choice_ivar, signed_scope_mvar, match_response_mvar, answer_ivar
        @question_name_ivar = question_name_ivar
        @choices_ivar = choices_ivar
        @choice_ivar = choice_ivar
        @signed_scope_mvar = signed_scope_mvar
        @match_response_mvar = match_response_mvar
        @answer_ivar = answer_ivar
      end

      def question_name
        @question_name_ivar.value
      end

      def query_id
        @query_id ||= SecureRandom.uuid
      end

      def choices= value
        # TODO: readonly?
        @choices_ivar.set value
      end

      def choice
        @choice_ivar.value
      end

      def signed_scope
        @signed_scope_mvar.take
      end

      def match_response= value
        # TODO: readonly?
        @match_response_mvar.put value
      end

      def ready_to_ask
        true # TODO: is this always true?
      end

      # @param value [ValueResponse, ErrorResponse]
      def answer= value
        # TODO: readonly?
        @answer_ivar.set value
      end

      def cancel exception
        @choices_ivar.fail exception unless @choices_ivar.complete?
        @answer_ivar.fail exception unless @answer_ivar.complete?
      end
    end
  end
end
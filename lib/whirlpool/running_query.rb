require 'concurrent'

module Whirlpool
  QueryCancelled = Class.new StandardError

  module Client
    # Makes a pair of classes, one for the client and one for the app,
    # which communicate using shared concurrency variables
    def self.make_pair &app_thread_constructor
      question_name_ivar = Concurrent::IVar.new
      choices_ivar = Concurrent::IVar.new
      choice_ivar = Concurrent::IVar.new
      identity_mvar = Concurrent::MVar.new
      identity_response_mvar = Concurrent::MVar.new
      answer_ivar = Concurrent::IVar.new
      app = AppInterface.new question_name_ivar, choices_ivar, choice_ivar, identity_mvar, identity_response_mvar, answer_ivar
      thread = yield app
      client = RunningQuery.new thread, question_name_ivar, choices_ivar, choice_ivar, identity_mvar, identity_response_mvar, answer_ivar
      client
    end

    class RunningQuery
      def initialize app_thread, question_name_ivar, choices_ivar, choice_ivar, identity_mvar, identity_response_mvar, answer_ivar
        @thread = app_thread
        @question_name_ivar = question_name_ivar
        @choices_ivar = choices_ivar
        @choice_ivar = choice_ivar
        @identity_mvar = identity_mvar
        @identity_response_mvar = identity_response_mvar
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

      def identity= value
        @identity_mvar.put value
      end

      def identity_response
        # TODO: readonly?
        @identity_response_mvar
      end

      def answer
        # TODO: readonly?
        @answer_ivar
      end

      def cancel
        exception = Whirlpool::QueryCancelled.new "User cancelled the query"
        @choice_ivar.fail exception unless @choice_ivar.complete?
        @thread.raise exception
      end
    end

    # TODO names
    class AppInterface
      def initialize question_name_ivar, choices_ivar, choice_ivar, identity_mvar, identity_response_mvar, answer_ivar
        @question_name_ivar = question_name_ivar
        @choices_ivar = choices_ivar
        @choice_ivar = choice_ivar
        @identity_mvar = identity_mvar
        @identity_response_mvar = identity_response_mvar
        @answer_ivar = answer_ivar
      end

      def question_name
        @question_name_ivar
      end

      def choices= value
        # TODO: readonly?
        @choices_ivar.set value
      end

      def choice
        @choice_ivar
      end

      def identity
        @identity_mvar
      end

      def identity_response= value
        # TODO: readonly?
        @identity_response_mvar.put value
      end

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
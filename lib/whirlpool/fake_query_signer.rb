require 'aquae/protos/messaging.pb'

module Whirlpool
  class FakeQuerySigner
    include Aquae::Messaging

    def initialize interface, plan
      @plan = plan
      @interface = interface
    end

    # Set the identity to be signed
    def identity= value={}
      p FakeQuerySigner::make_scope(@plan, value)
      @interface.signed_scope = FakeQuerySigner::make_scope(@plan, value)
    end

    def self.make_scope plan, identity
      Query::SignedScope.new(
        scope: Query::Scope.new(
          originalQuestion: Question.new(name: plan.root_query.name),
          nOnce: SecureRandom.hex,
          subjectIdentity: SignedIdentity.new(
            identity: PersonIdentity.new(identity)),
          plan: FakeQuerySigner::make_query_plan(plan, plan.root_query)))
    end

    def self.make_query_plan graph, spec
      Aquae::Messaging::QueryPlan.new(
        query: Question.new(name: spec.name),
        required_query: graph.required_queries(spec).map {|qs| FakeQuerySigner::make_query_plan graph, qs }
      )
    end
  end
end
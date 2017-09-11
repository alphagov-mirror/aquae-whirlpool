require 'securerandom'
require_relative 'local_question'
require_relative 'remote_question'
require_relative 'local_match'
require_relative 'remote_match'

module Viaduct
  # A query plan is a specific instance of a query for a specified query path
  class QueryPlan
    def initialize blocks, endpoint, this_node, query_tree, query_id=nil
      raise ArgumentError, "Query tree must be for a single query" unless query_tree.single_query?
      raise ArgumentError, "Query tree must not have any open choices" unless query_tree.choices_resolved?
      @blocks = blocks
      @endpoint = endpoint
      @this_node = this_node
      @tree = query_tree
      @query_id = query_id
    end

    # Returns an array of the matches required to service this query
    def matches
      @matches ||= all_impls.select(&:requires_matching?).map(&method(:make_match)).to_a
    end

    # The question that this query is asking
    def question
      @question ||= make_question @tree.root_query
    end

    # The nodes involved in the query
    def nodes
      all_impls.map(&:node).uniq
    end

    private

    # Returns the chosen implementation for this query in this plan
    def impl query_spec
      @tree.choices[query_spec].first
    end

    def all_impls
      @tree.all_choices
    end

    # Whether the passed query will be run on this node
    def local? query_spec
      impl(query_spec).node == @this_node
    end

    # Returns the query id for this query
    # (this may be supplied by the calling node, else one is generated)
    def query_id
      @query_id ||= generate_query_id
    end

    # Returns a question object that will answer the passed spec
    def make_question query_spec
      if local? query_spec
        required_questions = impl(query_spec).required_queries.map &method(:make_question)
        LocalQuestion.new query_spec.name, @blocks[query_spec.name], required_questions, query_id
      else
        node = impl(query_spec).node
        RemoteQuestion.new query_spec.name, @endpoint, node, query_id
      end
    end

    # Returns a match object that will set up a match for the passed impl
    def make_match impl
      if impl.node == @this_node
        LocalMatch.new nil, query_id #TODO
      else
        RemoteMatch.new impl.query_for, @endpoint, impl.node, query_id
      end
    end

    def generate_query_id
      SecureRandom.uuid
    end
  end
end
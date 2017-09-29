require_relative 'local_question'
require_relative 'remote_question'
require_relative 'local_match'
require_relative 'remote_match'
require_relative 'lazy_socket'

module Whirlpool
  # A query plan is a specific instance of a query for a specified query path
  class QueryPlan
    def initialize blocks, endpoint, this_node, query_tree, query_id=nil
      raise ArgumentError, "Query tree must be for a single query" unless query_tree.single_query?
      raise ArgumentError, "Query tree must not have any open choices" unless query_tree.choices_resolved?
      @blocks = blocks
      @this_node = this_node
      @tree = query_tree
      @query_id = query_id
      @sockets = Hash.new {|hash, node| hash[node] = LazySocket.new { endpoint.connect_to node } }
    end

    # Set the question and match classes in use
    [:remote_question, :local_question, :remote_match, :local_match].each do |class_symbol|
      class_name = class_symbol.to_s.split('_').map(&:capitalize).join
      define_singleton_method :"#{class_symbol}_class=" {|val| class_variable_set :"@@#{class_name}Class", val }
      class_variable_set :"@@#{class_name}Class", Whirlpool.const_get(class_name)
    end

    # Returns an array of the matches required to service this query
    def matches
      @matches ||= resolve_matches(@tree.root_query)
        .group_by(&:last)
        .flat_map {|via, impls| make_match via, impls.map(&:first) }.to_a
    end

    # The question that this query is asking
    def question
      @question ||= make_question @tree.root_query
    end

    # The nodes involved in the query
    def nodes
      all_impls.map(&:node).uniq
    end

    # Returns the query id for this query
    # (this may be supplied by the calling node, else one is generated)
    def query_id
      @query_id ||= generate_query_id
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

    # Works out all the matches that need to occur, and pairs them
    # with the node that will receive the identity data.
    def resolve_matches query_spec, match_via=nil
      match_via ||= (impl(query_spec) unless local?(query_spec))
      matching = impl(query_spec).requires_matching? ? [[impl(query_spec), match_via]] : []
      @tree.required_queries(query_spec)
        .map {|q| resolve_matches q, match_via }
        .flatten(1)
        .concat(matching)
    end

    # Returns a question object that will answer the passed spec
    def make_question query_spec
      if local? query_spec
        required_questions = impl(query_spec).required_queries.map &method(:make_question)
        @@LocalQuestionClass.new query_spec.name, @blocks[query_spec.name], required_questions, query_id
      else
        node = impl(query_spec).node
        @@RemoteQuestionClass.new query_spec.name, @sockets[node], node, query_id
      end
    end

    # Returns a match object that will set up a match for the passed impl
    def make_match via, impls
      if via.nil? || via.node == @this_node
        @@LocalMatchClass.new nil, query_id #TODO
      else
        @@RemoteMatchClass.new via.query_for, @sockets[via.node], via.node, impls, query_id
      end
    end
  end
end
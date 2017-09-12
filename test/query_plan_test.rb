require 'test-unit'
require 'aquae/query_graph'
require 'aquae/query_spec'
require 'aquae/node'
require_relative '../lib/viaduct/query_plan'

Viaduct::QueryPlan.remote_question_class = (TestRemoteQuestion = Struct.new :name, :endpoint, :node_id, :query_id)
Viaduct::QueryPlan.local_question_class = (TestLocalQuestion = Struct.new :name, :block, :required_questions, :query_id)
Viaduct::QueryPlan.remote_match_class = (TestRemoteMatch = Struct.new :question, :endpoint, :node_id, :impls, :query_id)
Viaduct::QueryPlan.local_match_class = (TestLocalMatch = Struct.new :name, :block, :required_questions, :query_id)

class QueryPlanTest < Test::Unit::TestCase
  def self.question_fixture name
    Aquae::QuerySpec.new name
  end

  def self.node_fixture name
    Aquae::Node.new name, nil, nil, nil
  end

  def self.match_fixture
    true
  end

  def self.choice_for node, parent, children=[], match=nil
    Aquae::QuerySpec::Implementation.new node, parent, children, match
  end

  def graph_of number
    fixtures = number.times.map(&:to_s).map(&QueryPlanTest.method(:question_fixture))
    graph = Aquae::QueryGraph.new
    fixtures.each &graph.method(:add_query)
    yield graph if block_given?
    graph
  end

  def query_plan_for query_tree
    Viaduct::QueryPlan.new({}, nil, ThisNode, query_tree)
  end

  ThisNode = node_fixture 'this'
  RemoteNode = node_fixture 'remote'
  RemoteNode2 = node_fixture 'remote2'

  # Makes a graph like:
  #
  #   Qm(remote)
  #
  def remote_question_with_matching_requirements
    graph_of(1) do |graph|
      parent = graph.leaf_queries.first
      graph.add_choice QueryPlanTest.choice_for RemoteNode, parent, [], QueryPlanTest.match_fixture
    end
  end

  # Makes a graph like:
  #
  #   Q(this) -> Q(remote) -> Q(remote)
  #
  def local_question_with_remote_question_with_required_question
    graph_of(3) do |graph|
      parent, child, grandchild = graph.leaf_queries
      graph.add_choice QueryPlanTest.choice_for ThisNode, parent, [child], QueryPlanTest.match_fixture
      graph.add_choice QueryPlanTest.choice_for RemoteNode, child, [grandchild], QueryPlanTest.match_fixture
      graph.add_choice QueryPlanTest.choice_for RemoteNode2, grandchild, [], QueryPlanTest.match_fixture
    end
  end

  # Makes a graph like:
  #
  #   Qm(this)
  #
  def local_question_with_matching_requirements
    graph_of(1) do |graph|
      parent = graph.leaf_queries.first
      graph.add_choice QueryPlanTest.choice_for ThisNode, parent, [], QueryPlanTest.match_fixture
    end
  end

  # Makes a graph like:
  #
  #   Q(this) -> Qm(remote)
  #
  def local_question_with_remote_matching_child
    graph_of(2) do |graph|
      parent, child = *graph.leaf_queries
      graph.add_choice QueryPlanTest.choice_for ThisNode, parent, [child]
      graph.add_choice QueryPlanTest.choice_for RemoteNode, child, [], QueryPlanTest.match_fixture
    end
  end

  # Makes a graph like:
  #
  #   Q(remote) --> Qm(remote2)
  #            \
  #             \-> Qm(remote2)
  #
  def remote_question_with_multiple_required_questions
    graph_of(3) do |graph|
      parent, *children = graph.leaf_queries
      graph.add_choice QueryPlanTest.choice_for RemoteNode, parent, children
      graph.add_choice QueryPlanTest.choice_for RemoteNode2, children.first, [], QueryPlanTest.match_fixture
      graph.add_choice QueryPlanTest.choice_for RemoteNode2, children.last, [], QueryPlanTest.match_fixture
    end
  end

  # Makes a graph like:
  #
  #   Q(this) --> Qm(remote)
  #          \
  #           \-> Qm(remote2)
  #
  def local_question_with_multiple_required_questions
    graph_of(3) do |graph|
      parent, *children = graph.leaf_queries
      graph.add_choice QueryPlanTest.choice_for ThisNode, parent, children
      graph.add_choice QueryPlanTest.choice_for RemoteNode, children.first, [], QueryPlanTest.match_fixture
      graph.add_choice QueryPlanTest.choice_for RemoteNode2, children.last, [], QueryPlanTest.match_fixture
    end
  end

  test 'question object is made for a remote question' do
    plan = query_plan_for remote_question_with_matching_requirements
    assert_instance_of TestRemoteQuestion, plan.question
  end

  test 'question object is made for a local question' do
    plan = query_plan_for local_question_with_matching_requirements
    assert_instance_of TestLocalQuestion, plan.question
  end

  test 'question objects are made for a local question with remote requirements' do
    plan = query_plan_for local_question_with_remote_matching_child
    assert_instance_of TestLocalQuestion, plan.question
    assert_equal 1, plan.question.required_questions.size
    assert_instance_of TestRemoteQuestion, plan.question.required_questions.first
  end

  test 'question object is not made for remote requirement of remote question' do
    plan = query_plan_for local_question_with_remote_question_with_required_question
    assert_instance_of TestLocalQuestion, plan.question
    assert_equal 1, plan.question.required_questions.size
    assert_equal '1', plan.question.required_questions.first.name
  end

  test 'match object made for local match' do
    plan = query_plan_for local_question_with_matching_requirements
    assert_equal 1, plan.matches.size
    assert_instance_of TestLocalMatch, plan.matches.first
  end

  test 'match object made for remote match' do
    plan = query_plan_for remote_question_with_matching_requirements
    assert_equal 1, plan.matches.size
    assert_instance_of TestRemoteMatch, plan.matches.first
  end

  test 'match object made for local question with remote match' do
    plan = query_plan_for local_question_with_remote_matching_child
    assert_equal 1, plan.matches.size
    assert_instance_of TestRemoteMatch, plan.matches.first
    assert_equal RemoteNode, plan.matches.first.node_id
  end

  test 'match object made for multiple remote matches with common ancestor' do
    plan = query_plan_for remote_question_with_multiple_required_questions
    assert_equal 1, plan.matches.size
    assert_equal RemoteNode, plan.matches.first.node_id
    assert_equal 2, plan.matches.first.impls.size
    plan.matches.first.impls.each {|impl| assert_equal RemoteNode2, impl.node }
  end

  test 'match objects made for multiple remote matches with different ancestors' do
    plan = query_plan_for local_question_with_multiple_required_questions
    assert_equal 2, plan.matches.size
    assert_include plan.matches.map(&:node_id).to_a, RemoteNode
    assert_include plan.matches.map(&:node_id).to_a, RemoteNode2
  end

  test 'match objects made for multiple remote matches and local match' do
    plan = query_plan_for local_question_with_remote_question_with_required_question
    assert_equal 2, plan.matches.size
    assert_true plan.matches.one? {|m| m.is_a? TestLocalMatch }
    remote = plan.matches.find {|m| m.is_a? TestRemoteMatch }
    assert_equal RemoteNode, remote.node_id
    assert_include remote.impls.map(&:node), RemoteNode
    assert_include remote.impls.map(&:node), RemoteNode2
  end
end
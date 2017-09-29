require 'aquae/protos/messaging.pb'

module Whirlpool
  # Question I can answer, with/out matching requirements
  class LocalQuestion
    include Aquae::Messaging

    attr_reader :name

    def initialize name, block, required_questions, query_id
      @name = name
      @block = block
      @required_questions = required_questions.map {|rq| [rq.name, rq]}.to_h
      @query_id = query_id
    end

    # Do transformation
    def answer
      puts "Answering #{name}..."
      answers = Hash.new {|hash, name| hash[name] = @required_questions[name].answer }
      begin
        value = @block.call answers #TODO: return value?
        value.is_a?(ValueResponse) ? value : ValueResponse.new #TODO: populate value
      rescue Exception => e
        ErrorResponse.new
      end
    end
  end
end
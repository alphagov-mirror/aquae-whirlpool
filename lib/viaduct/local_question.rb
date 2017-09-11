require 'aquae/protos/messaging.pb'

module Viaduct
  # Question I can answer, with/out matching requirements
  class LocalQuestion
    attr_reader :name

    def initialize name, block, required_questions, query_id
      @name = name
      @block = block
      @required_questions = required_questions.map {|rq| [rq.name, rq]}.to_h
    end

    # Do transformation
    def answer
      puts "Answering #{name}..."
      answers = Hash.new {|hash, name| p name, hash; hash[name] = @required_questions[name].answer }
      @block.call answers #TODO: return value?
    end
  end
end
module Viaduct
  class LoadedQuestionSet
    @@questions = {}

    def self.question name, &block
      @@questions[name] = block
    end

    def self.questions
      @@questions
    end
  end

  class QueryLoader
    # TODO: remove this incredible hack
    def self.load *files
      files.inject({}) do |hash, file|
        contents = File.read file
        code = <<-MODULE
          Class.new(LoadedQuestionSet) do
            #{contents}
          end
        MODULE
        klass = eval code
        hash.update klass.questions
      end
    end
  end
end
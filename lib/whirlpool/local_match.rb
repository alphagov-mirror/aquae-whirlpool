require 'aquae/protos/messaging.pb'

module Whirlpool
  # A match that needs to performed against a 'local' database
  # i.e. where this node is the data authority.
  class LocalMatch
    include Aquae::Messaging

    def initialize matcher, query_id
      @matcher = matcher
      @query_id = query_id
    end

    # Do matching??
    def match scope
      confident = @matcher.run_match scope.subjectIdentity
      response = QueryResponse.new queryId: @query_id
      if confident
        response.moreIdentityResponse = MoreIdentityResponse.new #TODO: fields
      else
        response.matchCompleteResponse = MatchCompleteResponse.new
      end
      response
    end

    def finish
      @matcher = nil
    end
  end

  class SimpleMatcher
    def initialize data
      @data = data
    end

    def run_match identity
      @match = @data.select {|id| potential_match? identity, id }
      return @match.one? || @match.none?
    end

    def potential_match? a, b
      (a.surname.nil? || a.surname == b.surname) &&
      (a.postcode.nil? || a.postcode == b.postcode) &&
      (a.birthYear.nil? || a.birthYear == b.birthYear) &&
      (a.initials.nil? || a.initials == b.initials)
    end
  end
end

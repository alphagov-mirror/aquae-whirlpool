# Whirlpool ![ALPHA](https://i.imgur.com/8QQeMH8.png)

Whirlpool is a Ruby implementation of an [AQuAE node](https://www.github.com/alphagov/aquae-specification) that asks questions and computes answers by interacting with other nodes as part of a federation.

Whirlpool can be integrated with numerous kinds of systems:

* a web server, to enable a personal data query to happen as part of an online journey,
* an API server, for personal data answers to be served to other services,
* a CRM system, to enable a personal data query to happen as part of a back-office workflow,
* or any other software system that needs to ask questions of a personal data network about citizens.

Whirlpool is the application-level software that enables all of these integrations to occur.

It can also be run as a standalone application and be loaded with business-logic rules. This allows it to operate as a query server, collecting required data from other nodes and serving answers using that data to clients, all as part of an AQuAE network.

Please note this is **ALPHA** quality software as the ecosystem won't be suitable for live use until v1.0. See the list of missing features below.

## Installing

A compiled gem version is not available on Rubygems yet.

Add `whirlpool` to your Gemfile:

    gem 'whirlpool', github: 'alphagov/whirlpool'

## Configuration

Configuration can be supplied to Whirlpool as a YAML file, to the following specification:

    ---
    metadata:   my.federation    # A federation file to load.
    this_node:  simon1           # The name of this node in the metadata.
    keyfile:    my.private.key   # The private key for the node.
    queryfiles:                  # A list of files to load containing local queries.
    - queries.rb

## Integrating

To create an integration, load the library and start an app instance.

    require 'whirlpool'
    config = Whirlpool::Configuration.new 'config.yml'
    app = Whirlpool::Application.new config

Now you can issue queries. Each query will start a new `Thread`, and return an object that can be used to give data to the thread.

    query = app.start_query

Set the question that you wish to ask, corresponding to a question in the metadata file.

    query.question_name = 'eligible?'

Whirlpool may offer you multiple choices for how the query can be implemented. Offer these to the user or make an appropriate decision. The methods will return futures that you can wait on or store for later.

    choices_promise = query.choices
    choices = choices_promise.value

    my_choice = choices.first # put your better decision logic here
    query.choice = my_choice

The choice tells you what identity information is required.

    my_choice.matching_requirements
    #<Aquae::Metadata::MatchingSpec required=[:surname, :postcode]>

Get your identity data signed via an appropriate route. For now, consent servers are not properly implemented so use a stub implementation.

    signer = Whirlpool::FakeQuerySigner.new query, my_choice
    signer.identity = {:surname => ..., :postcode => ..., ...}

Then ask for the answer.

    answer = query.answer.value

## `whirlpoold`

This is a standalone app that will operate an AQuAE node.

It accepts as command-line argument a YAML file for configuration to the above specification.

# frozen_string_literal: true

require "date"
require "erb"
require "pathname"
require "yaml"
require "dry/monads"

module Mihari
  module Services
    class RuleBuilder
      include Dry::Monads[:result]

      # @return [String]
      attr_reader :path_or_id

      #
      # Initialize
      #
      # @param [String] path_or_id
      #
      def initialize(path_or_id)
        @path_or_id = path_or_id
      end

      #
      # @return [Hash]
      #
      def data
        if Mihari::Rule.exists?(path_or_id)
          rule = Mihari::Rule.find(path_or_id)
          return rule.data
        end

        raise ArgumentError, "#{path_or_id} does not exist" unless Pathname(path_or_id).exist?

        YAML.safe_load(
          ERB.new(File.read(path_or_id)).result,
          permitted_classes: [Date, Symbol]
        )
      end

      def result
        Success RuleProxy.new(data)
      rescue StandardError => e
        Failure e
      end
    end
  end
end
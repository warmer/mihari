# frozen_string_literal: true

require "json"

module Mihari
  module Services
    #
    # proxy (or converter) class for rule
    # proxying rule schema data into analyzer & model
    #
    class RuleProxy
      include Mixins::FalsePositive

      # @return [Hash]
      attr_reader :data

      # @return [Array, nil]
      attr_reader :errors

      #
      # Initialize
      #
      # @param [Hash] data
      #
      def initialize(data)
        @data = data.deep_symbolize_keys
        @errors = nil

        validate!
      end

      #
      # @return [Boolean]
      #
      def errors?
        return false if @errors.nil?

        !@errors.empty?
      end

      def validate!
        contract = Schemas::RuleContract.new
        result = contract.call(data)

        @data = result.to_h
        @errors = result.errors

        raise ValidationError.new("Validation failed", errors) if errors?
      end

      def [](key)
        data key.to_sym
      end

      #
      # @return [String]
      #
      def id
        @id ||= data[:id]
      end

      #
      # @return [String]
      #
      def title
        @title ||= data[:title]
      end

      #
      # @return [String]
      #
      def description
        @description ||= data[:description]
      end

      #
      # @return [String]
      #
      def yaml
        @yaml ||= data.deep_stringify_keys.to_yaml
      end

      #
      # @return [Array<Hash>]
      #
      def queries
        @queries ||= data[:queries]
      end

      #
      # @return [Array<String>]
      #
      def data_types
        @data_types ||= data[:data_types]
      end

      #
      # @return [Array<String>]
      #
      def tags
        @tags ||= data[:tags]
      end

      #
      # @return [Array<String, RegExp>]
      #
      def falsepositives
        @falsepositives ||= data[:falsepositives].map { |fp| normalize_falsepositive fp }
      end

      #
      # @return [Array<Hash>]
      #
      def emitters
        @emitters ||= data[:emitters]
      end

      #
      # @return [Array<Hash>]
      #
      def enrichers
        @enrichers ||= data[:enrichers]
      end

      #
      # @return [Integer, nil]
      #
      def artifact_lifetime
        @artifact_lifetime ||= data[:artifact_lifetime] || data[:artifact_ttl]
      end

      #
      # @return [Mihari::Models::Rule]
      #
      def model
        rule = Mihari::Models::Rule.find(id)

        rule.title = title
        rule.description = description
        rule.data = data

        rule
      rescue ActiveRecord::RecordNotFound
        Mihari::Models::Rule.new(
          id: id,
          title: title,
          description: description,
          data: data
        )
      end

      #
      # @return [Mihari::Rule]
      #
      def analyzer
        Mihari::Rule.new self
      end

      class << self
        #
        # Load rule from YAML string
        #
        # @param [String] yaml
        #
        # @return [Mihari::Services::Rule]
        #
        def from_yaml(yaml)
          new YAML.safe_load(ERB.new(yaml).result, permitted_classes: [Date, Symbol])
        end

        #
        # @param [Mihari::Models::Rule] model
        #
        # @return [Mihari::Services::Rule]
        #
        def from_model(model)
          new model.data
        end
      end
    end
  end
end

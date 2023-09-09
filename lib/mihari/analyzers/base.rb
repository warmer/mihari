# frozen_string_literal: true

module Mihari
  module Analyzers
    class Base
      include Mixins::Configurable
      include Mixins::Retriable

      # @return [String]
      attr_reader :query

      # @return [Hash]
      attr_reader :options

      #
      # @param [String] query
      # @param [Hash, nil] options
      #
      def initialize(query, options: nil)
        @query = query
        @options = options || {}
      end

      #
      # @return [Integer, nil]
      #
      def interval
        @interval ||= options[:interval]
      end

      #
      # @return [Integer]
      #
      def retry_interval
        @retry_interval ||= options[:retry_interval] || Mihari.config.retry_interval
      end

      #
      # @return [Integer]
      #
      def retry_times
        @retry_times ||= options[:retry_times] || Mihari.config.retry_times
      end

      #
      # @return [Integer]
      #
      def pagination_limit
        @pagination_limit ||= options[:pagination_limit] || Mihari.config.pagination_limit
      end

      # @return [Array<String>, Array<Mihari::Artifact>]
      def artifacts
        raise NotImplementedError, "You must implement #{self.class}##{__method__}"
      end

      #
      # Normalize artifacts
      # - Convert data (string) into an artifact
      # - Reject an invalid artifact
      #
      # @return [Array<Mihari::Artifact>]
      #
      def normalized_artifacts
        retry_on_error(times: retry_times, interval: retry_interval) do
          @normalized_artifacts ||= artifacts.compact.sort.map do |artifact|
            # No need to set data_type manually
            # It is set automatically in #initialize
            artifact = artifact.is_a?(Artifact) ? artifact : Artifact.new(data: artifact)
            artifact.source = source
            artifact
          end.select(&:valid?).uniq(&:data)
        end
      end

      # @return [String]
      def class_name
        self.class.to_s.split("::").last
      end

      alias_method :source, :class_name

      private

      class << self
        #
        # Initialize an analyzer by query params
        #
        # @param [Hash] params
        #
        # @return [Mihari::Analyzers::Base]
        #
        def from_query(params)
          copied = params.deep_dup

          # convert params into arguments for initialization
          query = copied[:query]

          # delete analyzer and query
          %i[analyzer query].each do |key|
            copied.delete key
          end

          copied[:options] = copied[:options] || nil

          new(query, **copied)
        end

        def inherited(child)
          super
          Mihari.analyzers << child
        end
      end
    end
  end
end

# frozen_string_literal: true

require "whois-parser"

module Mihari
  module Enrichers
    #
    # Whois enricher
    #
    class Whois < Base
      # @return [Hash]
      attr_accessor :memo

      #
      # @param [Hash, nil] options
      #
      def initialize(options: nil)
        super(options: options)

        @memo = {}
      end

      #
      # Query IAIA Whois API
      #
      # @param [String] domain
      #
      # @return [Mihari::Models::WhoisRecord, nil]
      #
      def query(domain)
        domain = PublicSuffix.domain(domain)

        # check memo
        return memo[domain].dup if memo.key?(domain)

        record = whois.lookup(domain)
        parser = record.parser
        return nil if parser.available?

        whois_record = Models::WhoisRecord.new(
          domain: domain,
          created_on: get_created_on(parser),
          updated_on: get_updated_on(parser),
          expires_on: get_expires_on(parser),
          registrar: get_registrar(parser),
          contacts: get_contacts(parser)
        )

        # set memo
        memo[domain] = whois_record

        whois_record
      end

      def reset_cache
        @memo = {}
      end

      private

      #
      # @return [::Whois::Client]
      #
      def whois
        @whois ||= [].tap do |out|
          out << if timeout.nil?
            ::Whois::Client.new
          else
            ::Whois::Client.new(timeout: timeout)
          end
        end.last
      end

      #
      # Get created_on
      #
      # @param [::Whois::Parser] parser
      #
      # @return [Date, nil]
      #
      def get_created_on(parser)
        parser.created_on
      rescue ::Whois::AttributeNotImplemented
        nil
      end

      #
      # Get updated_on
      #
      # @param [::Whois::Parser] parser
      #
      # @return [Date, nil]
      #
      def get_updated_on(parser)
        parser.updated_on
      rescue ::Whois::AttributeNotImplemented
        nil
      end

      #
      # Get expires_on
      #
      # @param [::Whois::Parser] parser
      #
      # @return [Date, nil]
      #
      def get_expires_on(parser)
        parser.expires_on
      rescue ::Whois::AttributeNotImplemented
        nil
      end

      #
      # Get registrar
      #
      # @param [::Whois::Parser] parser
      #
      # @return [Hash, nil]
      #
      def get_registrar(parser)
        parser.registrar&.to_h
      rescue ::Whois::AttributeNotImplemented
        nil
      end

      #
      # Get contacts
      #
      # @param [::Whois::Parser] parser
      #
      # @return [Array<Hash>, nil]
      #
      def get_contacts(parser)
        parser.contacts.map(&:to_h)
      rescue ::Whois::AttributeNotImplemented
        nil
      end
    end
  end
end

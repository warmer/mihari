# frozen_string_literal: true

module Mihari
  module Models
    #
    # Artifact validator
    #
    class ArtifactValidator < ActiveModel::Validator
      def validate(record)
        return if record.data_type

        record.errors.add :data, "#{record.data} is not supported"
      end
    end

    #
    # Artifact model
    #
    class Artifact < ActiveRecord::Base
      belongs_to :alert

      has_one :autonomous_system, dependent: :destroy
      has_one :geolocation, dependent: :destroy
      has_one :whois_record, dependent: :destroy

      has_many :cpes, dependent: :destroy
      has_many :dns_records, dependent: :destroy
      has_many :ports, dependent: :destroy
      has_many :reverse_dns_names, dependent: :destroy

      include ActiveModel::Validations

      validates_with ArtifactValidator

      # @return [Array<Mihari::Tag>] Tags
      attr_accessor :tags

      # @return [String, nil] Rule ID
      attr_accessor :rule_id

      def initialize(*args, **kwargs)
        attrs = args.first || kwargs
        data_ = attrs[:data]

        raise TypeError if data_.is_a?(Array) || data_.is_a?(Hash)

        super(*args, **kwargs)

        self.data_type = DataType.type(data)

        @tags = []
        @rule_id = ""
      end

      #
      # Check uniqueness of artifact
      #
      # @param [Time, nil] base_time Base time to check decaying
      # @param [Integer, nil] artifact_lifetime Artifact lifetime (TTL) in seconds
      #
      # @return [Boolean] true if it is unique. Otherwise false.
      #
      def unique?(base_time: nil, artifact_lifetime: nil)
        artifact = self.class.joins(:alert).where(
          data: data,
          alert: { rule_id: rule_id }
        ).order(created_at: :desc).first
        return true if artifact.nil?

        # check whether the artifact is decayed or not
        return false if artifact_lifetime.nil?

        # use the current UTC time if base_time is not given (for testing)
        base_time ||= Time.now.utc

        decayed_at = base_time - (artifact_lifetime || -1).seconds
        artifact.created_at < decayed_at
      end

      #
      # Count artifacts
      #
      # @param [Mihari::Structs::Filters::Artifact::SearchFilter] filter
      #
      # @return [Integer]
      #
      def count(filter)
        relation = build_relation(filter)
        relation.distinct("artifact.id").count
      end

      #
      # Enrich whois record
      #
      # @param [Mihari::Enrichers::Whois] enricher
      #
      def enrich_whois(enricher = Enrichers::Whois.new)
        return unless can_enrich_whois?

        self.whois_record = WhoisRecord.build_by_domain(normalize_as_domain(data), enricher: enricher)
      end

      #
      # Enrich DNS records
      #
      # @param [Mihari::Enrichers::GooglePublicDNS] enricher
      #
      def enrich_dns(enricher = Enrichers::GooglePublicDNS.new)
        return unless can_enrich_dns?

        self.dns_records = DnsRecord.build_by_domain(normalize_as_domain(data), enricher: enricher)
      end

      #
      # Enrich reverse DNS names
      #
      # @param [Mihari::Enrichers::Shodan] enricher
      #
      def enrich_reverse_dns(enricher = Enrichers::Shodan.new)
        return unless can_enrich_reverse_dns?

        self.reverse_dns_names = ReverseDnsName.build_by_ip(data, enricher: enricher)
      end

      #
      # Enrich geolocation
      #
      # @param [Mihari::Enrichers::IPInfo] enricher
      #
      def enrich_geolocation(enricher = Enrichers::IPInfo.new)
        return unless can_enrich_geolocation?

        self.geolocation = Geolocation.build_by_ip(data, enricher: enricher)
      end

      #
      # Enrich AS
      #
      # @param [Mihari::Enrichers::IPInfo] enricher
      #
      def enrich_autonomous_system(enricher = Enrichers::IPInfo.new)
        return unless can_enrich_autonomous_system?

        self.autonomous_system = AutonomousSystem.build_by_ip(data, enricher: enricher)
      end

      #
      # Enrich ports
      #
      # @param [Mihari::Enrichers::Shodan] enricher
      #
      def enrich_ports(enricher = Enrichers::Shodan.new)
        return unless can_enrich_ports?

        self.ports = Port.build_by_ip(data, enricher: enricher)
      end

      #
      # Enrich CPEs
      #
      # @param [Mihari::Enrichers::Shodan] enricher
      #
      def enrich_cpes(enricher = Enrichers::Shodan.new)
        return unless can_enrich_cpes?

        self.cpes = CPE.build_by_ip(data, enricher: enricher)
      end

      #
      # Enrich all the enrichable relationships of the artifact
      #
      def enrich_all
        enrich_autonomous_system ipinfo
        enrich_dns
        enrich_geolocation ipinfo
        enrich_reverse_dns shodan
        enrich_whois
        enrich_ports shodan
        enrich_cpes shodan
      end

      ENRICH_METHODS_BY_ENRICHER = {
        Enrichers::Whois => %i[
          enrich_whois
        ],
        Enrichers::IPInfo => %i[
          enrich_autonomous_system
          enrich_geolocation
        ],
        Enrichers::Shodan => %i[
          enrich_ports
          enrich_cpes
          enrich_reverse_dns
        ],
        Enrichers::GooglePublicDNS => %i[
          enrich_dns
        ]
      }.freeze

      #
      # Enrich by name of enricher
      #
      # @param [Mihari::Enrichers::Base] enricher
      #
      def enrich_by_enricher(enricher)
        methods = ENRICH_METHODS_BY_ENRICHER[enricher.class] || []
        methods.each { |method| send(method, enricher) if respond_to?(method) }
      end

      class << self
        #
        # Search artifacts
        #
        # @param [Mihari::Structs::Filters::Artifact::SearchFilterWithPagination] filter
        #
        # @return [Array<Artifact>]
        #
        def search(filter)
          limit = filter.limit.to_i
          raise ArgumentError, "limit should be bigger than zero" unless limit.positive?

          page = filter.page.to_i
          raise ArgumentError, "page should be bigger than zero" unless page.positive?

          offset = (page - 1) * limit

          relation = build_relation(filter.without_pagination)
          relation.limit(limit).offset(offset).order(id: :desc)
        end

        #
        # Count artifacts
        #
        # @param [Mihari::Structs::Filters::Artifact::SearchFilter] filter
        #
        # @return [Integer]
        #
        def count(filter)
          relation = build_relation(filter)
          relation.distinct("artifacts.id").count
        end

        #
        # @param [Mihari::Structs::Filters::Artifact::SearchFilter] filter
        #
        # @return [Mihari::Models::Artifact]
        #
        def build_relation(filter)
          relation = eager_load(alert: :tags)

          relation = relation.where(alert: { rule_id: filter.rule_id }) if filter.rule_id
          relation = relation.where(alert: { tags: { name: filter.tag } }) if filter.tag
          relation = relation.where(data_type: filter.data_type) if filter.data_type
          relation = relation.where("artifacts.created_at >= ?", filter.from_at) if filter.from_at
          relation = relation.where("artifacts.created_at <= ?", filter.to_at) if filter.to_at

          relation
        end
      end

      private

      def ipinfo
        @ipinfo ||= Enrichers::IPInfo.new
      end

      def shodan
        @shodan ||= Enrichers::Shodan.new
      end

      def normalize_as_domain(url_or_domain)
        return url_or_domain if data_type == "domain"

        Addressable::URI.parse(url_or_domain).host
      end

      def can_enrich_whois?
        %w[domain url].include?(data_type) && whois_record.nil?
      end

      def can_enrich_dns?
        %w[domain url].include?(data_type) && dns_records.empty?
      end

      def can_enrich_reverse_dns?
        data_type == "ip" && reverse_dns_names.empty?
      end

      def can_enrich_geolocation?
        data_type == "ip" && geolocation.nil?
      end

      def can_enrich_autonomous_system?
        data_type == "ip" && autonomous_system.nil?
      end

      def can_enrich_ports?
        data_type == "ip" && ports.empty?
      end

      def can_enrich_cpes?
        data_type == "ip" && cpes.empty?
      end
    end
  end
end

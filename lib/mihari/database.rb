# frozen_string_literal: true

require "active_record"

class InitialSchema < ActiveRecord::Migration[6.1]
  def change
    create_table :tags, if_not_exists: true do |t|
      t.string :name, null: false
    end

    create_table :alerts, if_not_exists: true do |t|
      t.string :title, null: false
      t.string :description, null: true
      t.string :source, null: false
      t.timestamps
    end

    create_table :artifacts, if_not_exists: true do |t|
      t.string :data, null: false
      t.string :data_type, null: false
      t.belongs_to :alert, foreign_key: true
      t.timestamps
    end

    create_table :taggings, if_not_exists: true do |t|
      t.integer :tag_id
      t.integer :alert_id
    end

    add_index :taggings, :tag_id, if_not_exists: true
    add_index :taggings, [:tag_id, :alert_id], unique: true, if_not_exists: true
  end
end

class V3Schema < ActiveRecord::Migration[6.1]
  def change
    add_column :artifacts, :source, :string, if_not_exists: true
  end
end

class IPEnrichmentSchema < ActiveRecord::Migration[6.1]
  def change
    create_table :autonomous_systems, if_not_exists: true do |t|
      t.integer :asn, null: false
      t.belongs_to :artifact, foreign_key: true
    end

    create_table :geolocations, if_not_exists: true do |t|
      t.string :country, null: false
      t.string :country_code, null: false
      t.belongs_to :artifact, foreign_key: true
    end
  end
end

class DomainEnrichmentSchema < ActiveRecord::Migration[6.1]
  def change
    create_table :whois_records, if_not_exists: true do |t|
      t.text :text, null: false
      t.string :registrar
      t.date :created_on
      t.belongs_to :artifact, foreign_key: true
    end

    create_table :dns_records, if_not_exists: true do |t|
      t.string :resource, null: false
      t.string :value, null: false
      t.belongs_to :artifact, foreign_key: true
    end
  end
end

class ReverseDnsSchema < ActiveRecord::Migration[6.1]
  def change
    create_table :reverse_dns_names, if_not_exists: true do |t|
      t.string :name, null: false
      t.belongs_to :artifact, foreign_key: true
    end
  end
end

def adapter
  return "postgresql" if Mihari.config.database.start_with?("postgresql://", "postgres://")
  return "mysql2" if Mihari.config.database.start_with?("mysql2://")

  "sqlite3"
end

module Mihari
  class Database
    class << self
      def connect
        case adapter
        when "postgresql", "mysql2"
          ActiveRecord::Base.establish_connection(Mihari.config.database)
        else
          ActiveRecord::Base.establish_connection(
            adapter: adapter,
            database: Mihari.config.database
          )
        end

        # ActiveRecord::Base.logger = Logger.new STDOUT
        ActiveRecord::Migration.verbose = false

        InitialSchema.migrate(:up)
        V3Schema.migrate(:up)
        IPEnrichmentSchema.migrate(:up)
        DomainEnrichmentSchema.migrate(:up)
        ReverseDnsSchema.migrate(:up)
      rescue StandardError
        # Do nothing
      end

      def close
        ActiveRecord::Base.clear_active_connections!
        ActiveRecord::Base.connection.close
      end

      def destroy!
        return unless ActiveRecord::Base.connected?

        InitialSchema.migrate(:down)
        V3Schema.migrate(:down)
        IPEnrichmentSchema.migrate(:down)
        DomainEnrichmentSchema.migrate(:down)
        ReverseDnsSchema.migrate(:down)
      end
    end
  end
end

Mihari::Database.connect

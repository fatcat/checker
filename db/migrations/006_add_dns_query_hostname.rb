# frozen_string_literal: true

Sequel.migration do
  change do
    alter_table :hosts do
      add_column :dns_query_hostname, String, null: true
    end
  end
end

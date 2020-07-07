
module Sequel
  module Plugins
    module Upsert
      def self.configure(model, opts=OPTS)
        model.instance_exec do
          @upsert_plugin_identifying_columns = opts.fetch(:identifying_columns)
        end
      end

      module ClassMethods
        attr_reader :upsert_plugin_identifying_columns
      end

      module InstanceMethods
        # dirty stateful attribute because we can't pass any opts through to the _insert_dataset method
        attr_reader :upsert_plugin_upserting

        def upsert(opts = {})
          @upsert_plugin_upserting = true
          if postgres? || mysql?
            save(opts)
          else
            manual_upsert(opts)
          end
          load_values_from_previously_inserted_object unless id
          self
        rescue Sequel::NoExistingObject
          load_values_from_previously_inserted_object
        ensure
          @upsert_plugin_upserting = false
        end

        def load_values_from_previously_inserted_object
          if self.respond_to?(:id=)
            query = self.class.upsert_plugin_identifying_columns.each_with_object({}) do | column_name, q |
              q[column_name] = values[column_name]
            end
            self.id = model.where(query).single_record.id
          end
          refresh
        end

        def manual_upsert(opts)
          # Can use slice when we drop support for Ruby 2.4
          query = values.select{ |k, _| self.class.upsert_plugin_identifying_columns.include?(k) }
          existing_record = model.where(query).single_record
          if existing_record
            existing_record.update(values)
          else
            save(opts)
          end
        end

        # naughty override of Sequel private method to
        # avoid having to rewrite the whole save method logic
        def _insert_dataset
          if upsert_plugin_upserting
            if postgres?
              super.insert_conflict(update: values, target: self.class.upsert_plugin_identifying_columns)
            elsif mysql?
              columns_to_update = values.keys - self.class.upsert_plugin_identifying_columns
              super.on_duplicate_key_update(*columns_to_update)
            else
              super
            end
          else
            super
          end
        end

        def mysql?
          model.db.adapter_scheme.to_s =~ /mysql/
        end

        def postgres?
          model.db.adapter_scheme.to_s == "postgres"
        end
      end
    end
  end
end

require "digest"

module PgSearch
  class Configuration
    class Association
      attr_reader :columns

      def initialize(model, name, column_names)
        @model = model
        @name = name
        @columns = Array(column_names).map do |column_name, weight|

          if model.respond_to?(:translated?) && model.translated?(column_name)
            translation_model = "#{model.name}::Translation".constantize
            ForeignColumn.new(column_name, weight, translation_model, self)
          else
            ForeignColumn.new(column_name, weight, @model, self)
          end


        end
      end

      def table_name
        @model.reflect_on_association(@name).table_name
      end

      def join(primary_key)
        "LEFT OUTER JOIN (#{relation(primary_key).to_sql}) #{subselect_alias} ON #{subselect_alias}.id = #{primary_key}"
      end

      def subselect_alias
        Configuration.alias(table_name, @name, "subselect")
      end

      private

      def selects
        postgresql_version = @model.connection.send(:postgresql_version)

        columns.map do |column|
          case postgresql_version
          when 0..90000
            "array_to_string(array_agg(#{column.full_name}::text), ' ') AS #{column.alias}"
          else
            "string_agg(#{column.full_name}::text, ' ') AS #{column.alias}"
          end
        end.join(", ")
      end

      def relation(primary_key)
        query = @model.unscoped.joins(@name).select("#{primary_key} AS id, #{selects}").group(primary_key)
        if @model.respond_to? :translated?
          # NOTE: needs an outer join here to also find untranslated models
          prefix = @model.name.underscore
          query = query.joins "LEFT OUTER JOIN #{prefix}_translations ON #{@model.table_name}.id = #{prefix}_translations.#{prefix}_id"
        end
        query
      end
    end
  end
end

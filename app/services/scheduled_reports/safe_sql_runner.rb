# frozen_string_literal: true

module ScheduledReports
  class SafeSqlRunner
    MAX_ROWS = 10_000

    def self.run!(sql_text, shop_id)
      SafeSqlValidator.validate!(sql_text)
      sql = sql_text.to_s.gsub(SafeSqlValidator::SHOP_ID_PLACEHOLDER) do
        ActiveRecord::Base.sanitize_sql_array(["?", shop_id.to_i])
      end
      sql = sql.strip.sub(/;\z/, "")

      conn = ActiveRecord::Base.connection
      result = conn.exec_query(sql, "ScheduledShopReport")
      raise UnsafeSqlError, "Too many rows (#{result.rows.size}); narrow your query" if result.rows.size > MAX_ROWS

      result
    end
  end
end

# frozen_string_literal: true

module CodForm
  module Integrations
    module GoogleSheets
      # Google Sheets over plain HTTPS (ARCHITECTURE.md I.5, INT-1). No Google gem.
      #
      #   client = Client.new(integration)            # CodForm::Integration, provider google_sheets
      #   client.refresh!                             # new access token from the refresh token
      #   client.list_spreadsheets                    # [{"id" => …, "name" => …}]
      #   client.append_row(spreadsheet_id, sheet_name, values)
      #
      # Tokens live in cod_form_integrations.credentials and are never logged.
      # Errors: AuthError (reconnect needed, do not retry), TransientError (retry later),
      # RequestError (the request is wrong: missing sheet, no permission).
      class Client
        TOKEN_URL = "https://oauth2.googleapis.com/token"
        SHEETS_BASE = "https://sheets.googleapis.com/v4/spreadsheets"
        DRIVE_FILES_URL = "https://www.googleapis.com/drive/v3/files"
        SPREADSHEET_MIME = "application/vnd.google-apps.spreadsheet"
        EXPIRY_MARGIN = 60

        class Error < StandardError; end
        class AuthError < Error; end
        class TransientError < Error; end
        class RequestError < Error; end

        def self.configured?
          ENV.fetch("GOOGLE_SHEETS_CLIENT_ID", nil).present? && ENV.fetch("GOOGLE_SHEETS_CLIENT_SECRET", nil).present?
        end

        def initialize(integration)
          @integration = integration
        end

        # Exchanges the refresh token for an access token and stores it.
        def refresh!
          raise AuthError, "Google Sheets is not configured on this server" unless self.class.configured?

          refresh_token = credentials["refresh_token"].to_s
          raise AuthError, "Google account is not connected" if refresh_token.empty?

          response = CodForm::Tracking::Http.post_form(
            TOKEN_URL,
            { "client_id" => ENV.fetch("GOOGLE_SHEETS_CLIENT_ID", nil), "client_secret" => ENV.fetch("GOOGLE_SHEETS_CLIENT_SECRET", nil),
              "refresh_token" => refresh_token, "grant_type" => "refresh_token" }
          )
          raise TransientError, "token refresh: #{response.summary}" if response.retryable?

          data = response.json.is_a?(Hash) ? response.json : {}
          unless response.ok? && data["access_token"].to_s != ""
            # invalid_grant: the merchant revoked access or the refresh token expired.
            raise AuthError, "Google access was revoked. Reconnect Google Sheets."
          end

          @integration.update_columns(
            credentials: credentials.merge(
              "access_token" => data["access_token"],
              "expires_at" => (Time.current + data["expires_in"].to_i.seconds).utc.iso8601
            ),
            updated_at: Time.current
          )
          data["access_token"]
        end

        # Spreadsheets the app may see. With the drive.file scope that is the files the merchant
        # opened or created through this app.
        def list_spreadsheets
          query = URI.encode_www_form(
            "q" => "mimeType='#{SPREADSHEET_MIME}' and trashed=false",
            "fields" => "files(id,name)", "orderBy" => "modifiedTime desc", "pageSize" => "100"
          )
          data = authorized { |token| CodForm::Tracking::Http.get("#{DRIVE_FILES_URL}?#{query}", headers: bearer(token)) }
          Array(data["files"]).filter_map do |file|
            file.is_a?(Hash) ? { "id" => file["id"].to_s, "name" => file["name"].to_s } : nil
          end
        end

        # Titles of the tabs of one spreadsheet.
        def sheet_names(spreadsheet_id)
          url = "#{SHEETS_BASE}/#{escape(spreadsheet_id)}?fields=sheets.properties.title"
          data = authorized { |token| CodForm::Tracking::Http.get(url, headers: bearer(token)) }
          Array(data["sheets"]).filter_map { |sheet| sheet.dig("properties", "title") if sheet.is_a?(Hash) }
        end

        # Creates a spreadsheet owned by the merchant (works with the drive.file scope).
        def create_spreadsheet(title, sheet_name: "Orders")
          body = { "properties" => { "title" => title.to_s[0, 200] },
                   "sheets" => [{ "properties" => { "title" => sheet_name.to_s[0, 100] } }] }
          data = authorized { |token| CodForm::Tracking::Http.post_json(SHEETS_BASE, body, headers: bearer(token)) }
          { "id" => data["spreadsheetId"].to_s, "name" => title.to_s }
        end

        # Appends one row after the last row of the sheet.
        #   POST …/values/<sheet>!A1:append?valueInputOption=USER_ENTERED&insertDataOption=INSERT_ROWS
        # Values must come from RowBuilder (it neutralises formulas in buyer text).
        def append_row(spreadsheet_id, sheet_name, values)
          range = "#{quote_sheet(sheet_name)}!A1"
          url = "#{SHEETS_BASE}/#{escape(spreadsheet_id)}/values/#{escape(range)}:append" \
                "?valueInputOption=USER_ENTERED&insertDataOption=INSERT_ROWS"
          body = { "majorDimension" => "ROWS", "values" => [Array(values)] }
          data = authorized { |token| CodForm::Tracking::Http.post_json(url, body, headers: bearer(token)) }
          { "updated_range" => data.dig("updates", "updatedRange").to_s }
        end

        # True when the sheet has no values in its first row yet (so a header can be written).
        def empty_sheet?(spreadsheet_id, sheet_name)
          range = "#{quote_sheet(sheet_name)}!A1:A1"
          url = "#{SHEETS_BASE}/#{escape(spreadsheet_id)}/values/#{escape(range)}"
          data = authorized { |token| CodForm::Tracking::Http.get(url, headers: bearer(token)) }
          Array(data["values"]).empty?
        end

        private

        def credentials
          @integration.credentials.is_a?(Hash) ? @integration.credentials : {}
        end

        def access_token
          token = credentials["access_token"].to_s
          expires_at = begin
            Time.iso8601(credentials["expires_at"].to_s)
          rescue ArgumentError
            nil
          end
          return refresh! if token.empty? || expires_at.nil? || expires_at <= Time.current + EXPIRY_MARGIN

          token
        end

        # Runs the request with a valid token; one refresh-and-retry on 401.
        def authorized
          response = yield(access_token)
          response = yield(refresh!) if response.status == 401
          return response.json.is_a?(Hash) ? response.json : {} if response.ok?

          raise TransientError, response.summary if response.retryable?
          raise AuthError, "Google access was revoked. Reconnect Google Sheets." if response.status == 401

          reason = response.json.is_a?(Hash) ? response.json.dig("error", "status").to_s : ""
          raise RequestError, "#{response.summary} #{reason}".strip
        end

        def bearer(token)
          { "Authorization" => "Bearer #{token}" }
        end

        def escape(text)
          URI.encode_www_form_component(text.to_s).gsub("+", "%20")
        end

        # 'Sheet name' with single quotes doubled, as A1 notation requires for names with spaces.
        def quote_sheet(name)
          name = name.to_s.strip
          name = "Sheet1" if name.empty?
          "'#{name.gsub("'", "''")}'"
        end
      end
    end
  end
end

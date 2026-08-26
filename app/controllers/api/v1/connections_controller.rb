# frozen_string_literal: true

module Api
  module V1
    class ConnectionsController < BaseController
      before_action :set_connection, only: %i[update destroy]

      def index
        render json: { connections: current_user.connections.order(:provider, :label).map { |c| serialize(c) } }
      end

      def create
        connection = current_user.connections.create!(connection_params)
        render json: serialize(connection), status: :created
      end

      def update
        # A blank credential means "leave what's stored alone", so a client
        # editing a label can't wipe a password it never had.
        attributes = connection_params
        if attributes[:credentials].present?
          attributes[:credentials] = @connection.credentials.merge(attributes[:credentials].compact_blank)
        end

        @connection.update!(attributes)
        render json: serialize(@connection)
      end

      def destroy
        @connection.destroy!
        head :no_content
      end

      private

      def set_connection
        @connection = current_user.connections.find(params.expect(:id))
      end

      # Credentials never leave the server, in either direction.
      def serialize(connection)
        {
          id: connection.id,
          provider: connection.provider,
          label: connection.label,
          status: connection.status,
          settings: connection.settings,
          last_synced_at: connection.last_synced_at&.iso8601,
          last_error: connection.last_error,
          required_credentials: Connection.fields_for(connection.provider)[:credentials]
        }
      end

      def connection_params
        params.expect(connection: [:provider, :label, { settings: {}, credentials: {} }])
      end
    end
  end
end

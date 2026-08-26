# frozen_string_literal: true

class ConnectionsController < ApplicationController
  before_action :set_connection, only: %i[edit update destroy]

  def index
    @connections = current_user.connections.order(:provider, :label)
  end

  # Without a provider this renders a picker; with one it renders that
  # provider's own fields. The old single form showed the same generic fields
  # whatever you picked, which was the source of most of the confusion.
  def new
    # Not params.expect: the provider is genuinely optional here — absent means
    # "show the picker", and expect would raise instead.
    @provider = ConnectionProvider.find(params[:provider]) # rubocop:disable Rails/StrongParametersExpect
    return redirect_to helpers.connect_path(@provider) if @provider&.oauth?

    @connection = current_user.connections.new(provider: @provider&.key)
    @connection.label ||= @provider&.label
  end

  def edit
    @provider = ConnectionProvider.find(@connection.provider)
  end

  def create
    @connection = current_user.connections.new(connection_params)

    if @connection.save
      redirect_to connections_path, notice: "Connected #{@connection.label}."
    else
      @provider = ConnectionProvider.find(@connection.provider)
      render :new, status: :unprocessable_content
    end
  end

  def update
    # A blank credential field means "leave what's stored alone" rather than
    # "erase it", so editing a label never wipes a password.
    attrs = connection_params
    attrs[:credentials] = @connection.credentials.merge(attrs[:credentials].compact_blank) if attrs[:credentials]

    if @connection.update(attrs)
      redirect_to connections_path, notice: "Updated #{@connection.label}."
    else
      @provider = ConnectionProvider.find(@connection.provider)
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    label = @connection.label
    @connection.destroy!
    redirect_to connections_path, notice: "Disconnected #{label}."
  end

  private

  def set_connection
    @connection = current_user.connections.find(params.expect(:id))
  end

  def connection_params
    params.expect(connection: [:provider, :label, { settings: {}, credentials: {} }])
  end
end

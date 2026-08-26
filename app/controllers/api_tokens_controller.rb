# frozen_string_literal: true

class ApiTokensController < ApplicationController
  def index
    @api_tokens = current_user.api_tokens.order(created_at: :desc)
    @api_token = current_user.api_tokens.new
  end

  def create
    @api_token = current_user.api_tokens.new(name: params.require(:api_token)[:name])

    if @api_token.save
      # The plaintext exists only on this instance and is never recoverable, so
      # it rides the flash straight to the one page that shows it.
      flash[:token] = @api_token.plaintext_token
      redirect_to api_tokens_path, notice: "Created #{@api_token.name}."
    else
      @api_tokens = current_user.api_tokens.order(created_at: :desc)
      render :index, status: :unprocessable_content
    end
  end

  def destroy
    token = current_user.api_tokens.find(params.expect(:id))
    token.destroy!
    redirect_to api_tokens_path, notice: "Revoked #{token.name}."
  end
end

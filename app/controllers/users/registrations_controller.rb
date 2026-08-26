# frozen_string_literal: true

module Users
  # Devise's built-in account editor is replaced by /account, which splits
  # profile fields (no password needed) from email and password (which do).
  class RegistrationsController < Devise::RegistrationsController
    def edit
      redirect_to account_path
    end
  end
end

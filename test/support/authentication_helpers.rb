# frozen_string_literal: true

# Shared authentication configuration for tests that need a logged-in user.
#
# Usage:
#   configure_authentication(user)                # basic: authenticate only
#   configure_authentication(user, authorize: true)  # authorize with permissive lambda
#   configure_authentication(user, authorize: :admin) # authorize requiring admin?
#
module AuthenticationHelpers
  private

  def configure_authentication(user, authorize: nil)
    SourceMonitor.configure do |config|
      config.authentication.current_user_method = :current_user
      config.authentication.user_signed_in_method = :user_signed_in?

      config.authentication.authenticate_with lambda { |controller|
        controller.singleton_class.define_method(:current_user) { user }
        controller.singleton_class.define_method(:user_signed_in?) { user.present? }
      }

      case authorize
      when :admin
        config.authentication.authorize_with lambda { |controller|
          raise ActionController::RoutingError, "Not Found" unless user&.admin?
        }
      when true
        config.authentication.authorize_with lambda { |_controller| true }
      end
    end
  end
end

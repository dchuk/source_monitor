# Passwordless Authentication (Magic Links)

Alternative to password-based auth. Based on 37signals patterns.

## Philosophy

Auth is simple. A basic system is ~150 lines of code total. You get full control, no bloat, and easier maintenance.

## Core Models

### Identity Model

```ruby
# app/models/identity.rb
class Identity < ApplicationRecord
  has_secure_password validations: false

  has_many :sessions, dependent: :destroy
  has_many :magic_links, dependent: :destroy
  has_one :user, dependent: :destroy

  validates :email_address, presence: true, uniqueness: { case_sensitive: false }
  validates :email_address, format: { with: URI::MailTo::EMAIL_REGEXP }

  normalizes :email_address, with: -> { _1.strip.downcase }

  def send_magic_link(purpose: "sign_in")
    magic_link = magic_links.create!(purpose: purpose)
    MagicLinkMailer.sign_in_instructions(magic_link).deliver_later
    magic_link
  end
end
```

### Magic Link Model

```ruby
# app/models/magic_link.rb
class MagicLink < ApplicationRecord
  CODE_LENGTH = 6

  belongs_to :identity

  before_create :set_code
  before_create :set_expiration

  scope :unused, -> { where(used_at: nil) }
  scope :active, -> { unused.where("expires_at > ?", Time.current) }

  def self.authenticate(code)
    active.find_by(code: code.upcase)&.tap do |magic_link|
      magic_link.update!(used_at: Time.current)
    end
  end

  def expired?
    expires_at < Time.current
  end

  def used?
    used_at.present?
  end

  def valid_for_use?
    !expired? && !used?
  end

  private

  def set_code
    self.code = SecureRandom.alphanumeric(CODE_LENGTH).upcase
  end

  def set_expiration
    self.expires_at = 15.minutes.from_now
  end
end
```

### Session Model

```ruby
# app/models/session.rb
class Session < ApplicationRecord
  belongs_to :identity

  has_secure_token length: 36

  def active?
    created_at > 30.days.ago
  end
end
```

## Controllers

### Sessions Controller

```ruby
class SessionsController < ApplicationController
  allow_unauthenticated_access only: [:new, :create]

  def new
  end

  def create
    if identity = Identity.find_by(email_address: params[:email_address])
      identity.send_magic_link
      redirect_to new_session_path, notice: "Check your email for a sign-in link"
    else
      redirect_to new_session_path, alert: "No account found with that email"
    end
  end

  def destroy
    terminate_session
    redirect_to root_path
  end
end
```

### Magic Links Controller

```ruby
class Sessions::MagicLinksController < ApplicationController
  allow_unauthenticated_access

  def show
    if magic_link = MagicLink.authenticate(params[:code])
      start_new_session_for(magic_link.identity)
      redirect_to session.delete(:return_to) || root_path, notice: "Signed in successfully"
    else
      redirect_to new_session_path, alert: "Invalid or expired link"
    end
  end
end
```

## Testing

```ruby
# test/models/identity_test.rb
class IdentityTest < ActiveSupport::TestCase
  test "normalizes email address to lowercase" do
    identity = Identity.create!(email_address: "TEST@EXAMPLE.COM")
    assert_equal "test@example.com", identity.email_address
  end

  test "validates email format" do
    identity = Identity.new(email_address: "invalid")
    assert_not identity.valid?
    assert_includes identity.errors[:email_address], "is invalid"
  end

  test "sends magic link" do
    identity = identities(:david)

    assert_difference -> { identity.magic_links.count }, 1 do
      assert_enqueued_emails 1 do
        identity.send_magic_link
      end
    end
  end
end

# test/models/magic_link_test.rb
class MagicLinkTest < ActiveSupport::TestCase
  test "generates 6-character code" do
    magic_link = MagicLink.create!(identity: identities(:david))
    assert_equal 6, magic_link.code.length
    assert_match(/\A[A-Z0-9]+\z/, magic_link.code)
  end

  test "expires after 15 minutes" do
    magic_link = MagicLink.create!(identity: identities(:david))
    assert magic_link.valid_for_use?

    travel 16.minutes do
      assert magic_link.expired?
      assert_not magic_link.valid_for_use?
    end
  end

  test "authenticates with valid code" do
    magic_link = MagicLink.create!(identity: identities(:david))
    authenticated = MagicLink.authenticate(magic_link.code)

    assert_equal magic_link, authenticated
    assert authenticated.used?
  end

  test "does not authenticate used codes" do
    magic_link = MagicLink.create!(identity: identities(:david))
    MagicLink.authenticate(magic_link.code)
    assert_nil MagicLink.authenticate(magic_link.code)
  end
end

# test/controllers/sessions_controller_test.rb
class SessionsControllerTest < ActionDispatch::IntegrationTest
  test "create sends magic link" do
    identity = identities(:david)

    assert_enqueued_emails 1 do
      post session_path, params: { email_address: identity.email_address }
    end

    assert_redirected_to new_session_path
  end

  test "destroy terminates session" do
    sign_in_as identities(:david)
    delete session_path

    assert_redirected_to root_path
    assert_nil cookies[:session_token]
  end
end
```

### Test Helper

```ruby
# test/test_helper.rb
class ActionDispatch::IntegrationTest
  def sign_in_as(identity)
    session_record = identity.sessions.create!
    cookies.signed[:session_token] = session_record.token
  end

  def sign_out
    cookies.delete(:session_token)
  end
end
```

## Security

- Use signed cookies with `httponly: true` and `same_site: :lax`
- Magic links expire in 15 minutes
- Magic links are one-time use
- Rate limit login attempts
- Clean up old sessions with a recurring job

```ruby
# app/jobs/session_cleanup_job.rb
class SessionCleanupJob < ApplicationJob
  def perform
    Session.where("created_at < ?", 30.days.ago).delete_all
    MagicLink.where("expires_at < ?", 1.day.ago).delete_all
  end
end
```

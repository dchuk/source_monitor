# Event Tracking Patterns

## Philosophy: Domain Event Records, Not Generic Tracking

Events are rich domain models (CardMoved, CommentAdded) — not generic Event rows with JSON blobs.

## Domain Event Records

```ruby
# GOOD: Rich domain event
class CardMoved < ApplicationRecord
  belongs_to :card
  belongs_to :from_column, class_name: "Column"
  belongs_to :to_column, class_name: "Column"
  belongs_to :creator

  has_one :activity, as: :subject, dependent: :destroy

  after_create_commit :create_activity
  after_create_commit :broadcast_update_later
  after_create_commit :deliver_webhooks_later

  validates :card, :from_column, :to_column, presence: true

  def description
    "#{creator.name} moved #{card.title} from #{from_column.name} to #{to_column.name}"
  end

  private

  def create_activity
    Activity.create!(subject: self, creator: creator)
  end

  def broadcast_update_later
    card.broadcast_replace_later
  end

  def deliver_webhooks_later
    WebhookDeliveryJob.perform_later(self)
  end
end

# BAD: Generic event blob
Event.create(event_type: "card.moved", data: { card_id: 1 })
```

## Activity Feed (Polymorphic)

```ruby
class Activity < ApplicationRecord
  belongs_to :subject, polymorphic: true # CardMoved, CommentAdded, etc.
  belongs_to :creator, optional: true

  scope :recent, -> { order(created_at: :desc).limit(50) }
end
```

## Webhook System

```ruby
# Webhook endpoint configuration
class WebhookEndpoint < ApplicationRecord
  has_many :deliveries, class_name: "WebhookDelivery", dependent: :destroy

  validates :url, presence: true, format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]) }
  validates :events, presence: true

  serialize :events, coder: JSON

  def subscribed_to?(event_type)
    events.include?(event_type)
  end
end

# Delivery tracking
class WebhookDelivery < ApplicationRecord
  belongs_to :webhook_endpoint
  belongs_to :event, polymorphic: true

  enum :status, { pending: 0, delivered: 1, failed: 2 }

  scope :pending, -> { where(status: :pending) }
  scope :failed, -> { where(status: :failed) }
end
```

## Webhook Delivery Job

```ruby
class WebhookDeliveryJob < ApplicationJob
  queue_as :webhooks
  retry_on Net::OpenTimeout, wait: :polynomially_longer, attempts: 5

  def perform(event)
    WebhookEndpoint.all.select { |ep| ep.subscribed_to?(event.class.name.underscore) }.each do |endpoint|
      delivery = endpoint.deliveries.create!(event: event, status: :pending)
      response = deliver(endpoint.url, payload(event))
      delivery.update!(status: :delivered, response_code: response.code)
    rescue => e
      delivery&.update!(status: :failed, error_message: e.message)
    end
  end

  private

  def deliver(url, body)
    Net::HTTP.post(URI(url), body.to_json, "Content-Type" => "application/json")
  end

  def payload(event)
    { type: event.class.name.underscore, data: event.as_json, timestamp: Time.current.iso8601 }
  end
end
```

## Testing Events

```ruby
# test/models/card_moved_test.rb
require "test_helper"

class CardMovedTest < ActiveSupport::TestCase
  test "creates activity on create" do
    card = cards(:one)
    assert_difference "Activity.count", 1 do
      CardMoved.create!(
        card: card,
        from_column: columns(:todo),
        to_column: columns(:done),
        creator: users(:one)
      )
    end
  end

  test "#description includes details" do
    moved = card_moveds(:recent)
    assert_match moved.card.title, moved.description
    assert_match moved.from_column.name, moved.description
  end
end
```

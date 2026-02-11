---
name: active-storage-setup
description: Configures Active Storage for file uploads with variants and direct uploads. Use when adding file uploads, image attachments, document storage, generating thumbnails, or when user mentions Active Storage, file upload, attachments, or image processing.
allowed-tools: Read, Write, Edit, Bash, Glob, Grep
---

# Active Storage Setup for Rails 8

## Overview

Active Storage handles file uploads in Rails:
- Cloud storage (S3, GCS, Azure) or local disk
- Image variants (thumbnails, resizing)
- Direct uploads from browser
- Polymorphic attachments

## Quick Start

```bash
bin/rails active_storage:install
bin/rails db:migrate
bundle add image_processing
```

## Configuration

```yaml
# config/storage.yml
local:
  service: Disk
  root: <%= Rails.root.join("storage") %>

test:
  service: Disk
  root: <%= Rails.root.join("tmp/storage") %>

amazon:
  service: S3
  access_key_id: <%= Rails.application.credentials.dig(:aws, :access_key_id) %>
  secret_access_key: <%= Rails.application.credentials.dig(:aws, :secret_access_key) %>
  region: eu-west-1
  bucket: <%= Rails.application.credentials.dig(:aws, :bucket) %>
```

```ruby
# config/environments/development.rb
config.active_storage.service = :local

# config/environments/production.rb
config.active_storage.service = :amazon
```

## Model Attachments

### Single Attachment

```ruby
class User < ApplicationRecord
  has_one_attached :avatar do |attachable|
    attachable.variant :thumb, resize_to_limit: [100, 100]
    attachable.variant :medium, resize_to_limit: [300, 300]
  end
end
```

### Multiple Attachments

```ruby
class Event < ApplicationRecord
  has_many_attached :photos
  has_many_attached :documents
end
```

## Validations

### Manual Validation

```ruby
class User < ApplicationRecord
  has_one_attached :avatar

  validate :acceptable_avatar

  private

  def acceptable_avatar
    return unless avatar.attached?

    unless avatar.blob.byte_size <= 5.megabytes
      errors.add(:avatar, "is too large (max 5MB)")
    end

    acceptable_types = ["image/jpeg", "image/png", "image/webp"]
    unless acceptable_types.include?(avatar.content_type)
      errors.add(:avatar, "must be a JPEG, PNG, or WebP")
    end
  end
end
```

### With active_storage_validations Gem

```ruby
gem "active_storage_validations"

class User < ApplicationRecord
  has_one_attached :avatar

  validates :avatar,
    content_type: ["image/png", "image/jpeg", "image/webp"],
    size: { less_than: 5.megabytes }
end
```

## Image Variants

```ruby
# Resize to fit (maintains aspect ratio)
resize_to_limit: [300, 300]

# Resize and crop to exact dimensions
resize_to_fill: [300, 300]

# With format conversion
resize_to_limit: [300, 300], format: :webp, saver: { quality: 80 }
```

### Using in Views

```erb
<% if user.avatar.attached? %>
  <%= image_tag user.avatar.variant(:thumb), alt: user.name %>
<% else %>
  <%= image_tag "default-avatar.png", alt: "Default" %>
<% end %>
```

## Testing Attachments (Minitest)

### Model Test

```ruby
# test/models/user_test.rb
require "test_helper"

class UserAttachmentTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
  end

  test "attaches an avatar" do
    @user.avatar.attach(
      io: File.open(Rails.root.join("test/fixtures/files/avatar.jpg")),
      filename: "avatar.jpg",
      content_type: "image/jpeg"
    )

    assert @user.avatar.attached?
  end

  test "rejects oversized avatar" do
    @user.avatar.attach(
      io: StringIO.new("x" * 6.megabytes),
      filename: "large.jpg",
      content_type: "image/jpeg"
    )

    assert_not @user.valid?
    assert_includes @user.errors[:avatar], "is too large (max 5MB)"
  end

  test "rejects invalid content type" do
    @user.avatar.attach(
      io: File.open(Rails.root.join("test/fixtures/files/document.pdf")),
      filename: "doc.pdf",
      content_type: "application/pdf"
    )

    assert_not @user.valid?
    assert @user.errors[:avatar].any?
  end
end
```

### Controller Test

```ruby
# test/controllers/users_controller_test.rb
require "test_helper"

class UsersUploadTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in @user
  end

  test "uploads avatar" do
    avatar = fixture_file_upload("avatar.jpg", "image/jpeg")

    patch user_path(@user), params: { user: { avatar: avatar } }

    assert @user.reload.avatar.attached?
  end

  test "removes avatar" do
    @user.avatar.attach(
      io: File.open(Rails.root.join("test/fixtures/files/avatar.jpg")),
      filename: "avatar.jpg",
      content_type: "image/jpeg"
    )

    delete remove_avatar_user_path(@user)

    assert_not @user.reload.avatar.attached?
  end
end
```

### Fixtures Setup

Place test files in `test/fixtures/files/`:
```
test/fixtures/files/
├── avatar.jpg
├── document.pdf
└── photo.png
```

## Controller Handling

```ruby
class UsersController < ApplicationController
  def update
    if @user.update(user_params)
      redirect_to @user, notice: "Profile updated"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def remove_avatar
    @user.avatar.purge
    redirect_to edit_user_path(@user), notice: "Avatar removed"
  end

  private

  def user_params
    params.require(:user).permit(:name, :email, :avatar)
  end
end
```

### Multiple Uploads

```ruby
def event_params
  params.require(:event).permit(:name, photos: [], documents: [])
end
```

## Forms

```erb
<%= form_with model: @user do |f| %>
  <div>
    <%= f.label :avatar %>
    <%= f.file_field :avatar, accept: "image/png,image/jpeg,image/webp" %>

    <% if @user.avatar.attached? %>
      <%= image_tag @user.avatar.variant(:thumb), class: "rounded mt-2" %>
    <% end %>
  </div>
  <%= f.submit %>
<% end %>
```

## Direct Uploads

```javascript
// app/javascript/application.js
import * as ActiveStorage from "@rails/activestorage"
ActiveStorage.start()
```

```erb
<%= f.file_field :photos, multiple: true, direct_upload: true %>
```

## Performance Tips

```ruby
# Prevent N+1 on attachments
User.with_attached_avatar.limit(10)

# Multiple attachments
Event.with_attached_photos.with_attached_documents
```

## Checklist

- [ ] Active Storage installed and migrated
- [ ] Storage service configured
- [ ] Image processing gem added
- [ ] Attachment added to model
- [ ] Validations added (type, size)
- [ ] Variants defined
- [ ] Controller permits attachment params
- [ ] Tests written for attachments
- [ ] All tests GREEN

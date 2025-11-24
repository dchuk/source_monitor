# Rails Engine Asset Pipeline Guide

## Supporting Both Sprockets and Propshaft

### Core Principle

Support both asset pipelines to maximize compatibility with parent Rails apps. Propshaft is the modern standard, but Sprockets remains widely used in existing applications.

---

## Setup: Asset Bundling

Use `cssbundling-rails` and `jsbundling-rails` for maximum flexibility.

```ruby
# Add to gemspec
gem.add_dependency "cssbundling-rails"
gem.add_dependency "jsbundling-rails"
```

**Note:** Generators don't work inside engines. Install in a dummy app first, then manually move files to the engine.

```bash
cd test/dummy
rails javascript:install:esbuild
rails css:install:tailwind
# Move generated files back to engine root
```

---

## Asset Organization

### Directory Structure

```
app/assets/
  ├── builds/ENGINE_NAME/     # Bundled CSS/JS (auto-exposed)
  ├── images/ENGINE_NAME/     # Image files
  ├── svgs/ENGINE_NAME/       # SVG files
  └── config/                 # Manifest files (optional)
```

**Rule:** Always namespace asset directories with your engine name to prevent conflicts.

---

## Configuring engine.rb

### Basic Setup (Works for Both Pipelines)

```ruby
module YourEngine
  class Engine < ::Rails::Engine
    isolate_namespace YourEngine

    initializer "your_engine.assets" do |app|
      if app.config.respond_to?(:assets)
        # Expose asset directories
        app.config.assets.paths << Engine.root.join("app", "assets", "builds").to_s
        app.config.assets.paths << Engine.root.join("app", "assets", "images").to_s
        app.config.assets.paths << Engine.root.join("app", "assets", "svgs").to_s
      end
    end
  end
end
```

This configuration:

- Exposes the `builds` directory (bundled assets)
- Exposes the `images` directory
- Exposes the `svgs` directory
- Works automatically with Propshaft
- Requires additional configuration for Sprockets (see below)

---

## Sprockets-Specific Configuration

For Sprockets to properly precompile assets referenced in CSS (via `url()`), use one of these approaches:

### Option 1: Programmatic Precompile (Recommended)

```ruby
initializer "your_engine.assets" do |app|
  if app.config.respond_to?(:assets)
    # Add paths
    app.config.assets.paths << Engine.root.join("app", "assets", "builds").to_s
    app.config.assets.paths << Engine.root.join("app", "assets", "images").to_s
    app.config.assets.paths << Engine.root.join("app", "assets", "svgs").to_s

    # Configure precompilation for Sprockets
    asset_paths = [
      ["app", "assets", "images"],
      ["app", "assets", "images", "your_engine"],
      ["app", "assets", "svgs"],
    ]

    paths_to_precompile = asset_paths.flat_map do |path|
      Dir[Engine.root.join(*path, "**", "*")].filter_map do |file|
        next unless File.file?(file)
        Pathname.new(file).relative_path_from(Engine.root.join(*path)).to_s
      end
    end

    app.config.assets.precompile += paths_to_precompile
  end
end
```

**Critical:** Paths must be relative from the asset directory (e.g., `your_engine/logo.png`, not `app/assets/images/your_engine/logo.png`).

### Option 2: Manual Precompile Array

```ruby
initializer "your_engine.assets" do |app|
  if app.config.respond_to?(:assets)
    app.config.assets.paths << Engine.root.join("app", "assets", "images").to_s
    app.config.assets.precompile += %w[ your_engine/logo.png your_engine/icon.svg ]
  end
end
```

### Option 3: Manifest File

Create `app/assets/config/your_engine_manifest.js`:

```javascript
//= link_tree ../builds
//= link_tree ../images
//= link_tree ../svgs
```

Then in `engine.rb`:

```ruby
initializer "your_engine.assets" do |app|
  if defined?(::Sprockets)
    app.config.assets.precompile += %w[your_engine_manifest.js]
  end
end
```

---

## Using Assets

### In Views

```erb
<%= image_tag 'your_engine/logo.png' %>
<%= image_tag 'your_engine/icon.svg' %>
```

### In CSS

```css
.logo {
	background-image: url("your_engine/logo.png");
}
```

**Propshaft behavior:** Automatically finds assets and adds digest hashes.
**Sprockets behavior:** Requires files to be in the precompile array.

---

## Key Differences Between Pipelines

| Aspect                   | Propshaft                | Sprockets                         |
| ------------------------ | ------------------------ | --------------------------------- |
| Asset finding            | Automatic from paths     | Requires precompile configuration |
| CSS url() references     | Works automatically      | Needs explicit precompile setup   |
| Configuration complexity | Minimal                  | More involved                     |
| Prefix flexibility       | Can work with or without | Requires namespace prefix         |

---

## Testing Checklist

- [ ] Test in a Sprockets-based app
- [ ] Test in a Propshaft-based app
- [ ] Verify `image_tag` works in views
- [ ] Verify `url()` references work in CSS
- [ ] Confirm digest hashes are applied in production
- [ ] Check for asset path conflicts with parent app

---

## Quick Decision Tree

**Q: Do bundled assets in `app/assets/builds` need configuration?**
A: No, they're auto-exposed to both pipelines.

**Q: Do images/SVGs need configuration?**
A: Yes. Add paths with `app.config.assets.paths <<`. For Sprockets, also add to precompile array.

**Q: Are CSS `url()` references working?**
A: Propshaft: automatic. Sprockets: add files to precompile array.

**Q: Should I namespace asset directories?**
A: Yes, always use `your_engine/` prefix to prevent conflicts.

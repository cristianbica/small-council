# Custom `.rb` Configuration Pattern

## Purpose

Avoid time-consuming diffs from `rails app:update` by keeping app-specific overrides separate from Rails-generated files.

## The Problem

When you run `rails app:update`, Rails overwrites its generated configuration files:
- `config/application.rb`
- `config/environments/*.rb`
- `config/initializers/*.rb`

If you've modified these files, you face painful 3-way merges during every upgrade.

## The Solution

Use `.custom.rb` files for all app-specific overrides:
- Rails generates files → overwritten on update
- `.custom.rb` files → survive updates untouched

These files are tracked in git so teams share configuration, but they remain separate from Rails-generated files.

## Load Order

```
1. config/application.rb              (Rails generated)
2. config/application.custom.rb       (your overrides, if exists)
3. config/environments/#{env}.rb      (Rails generated)
4. config/environments/#{env}.custom.rb (your overrides, via initializer)
5. config/initializers/*.rb            (Rails + app initializers)
```

## Files

| File | Purpose |
|------|---------|
| `config/application.custom.rb` | Global app configuration hooks |
| `config/environments/*.custom.rb` | Environment-specific overrides |

## Git Strategy

These `.custom.rb` files are tracked in git:
- Teams share the same configuration
- Updates don't conflict with Rails-generated files
- Project conventions are preserved

## Idempotency Warning

**Critical**: These files run on every Rails boot. All code must be idempotent:

```ruby
# GOOD: Safe to run multiple times
config.hosts << ENV["APP_HOST"] if ENV["APP_HOST"].present?

# BAD: Duplicates on each boot
config.hosts << "myhost.com"  # Don't do this!
```

## Usage Examples

### Add Custom Hosts (Development)

```ruby
# config/environments/development.custom.rb
Rails.application.configure do
  config.hosts << "myapp.local" if Rails.env.development?
end
```

### Custom Initializer Loading

```ruby
# config/application.custom.rb
module SmallCouncil
  class Application < Rails::Application
    initializer :load_custom_initializers, after: :load_config_initializers do
      Dir[Rails.root.join("config/initializers/*.custom.rb")].each do |file|
        load file
      end
    end
  end
end
```

## Upgrading Rails

With this pattern:
1. Run `rails app:update` - it overwrites Rails files
2. Your `.custom.rb` files remain untouched
3. Review diffs in generated files (should be minimal)
4. Move any new overrides to appropriate `.custom.rb` files

## See Also

- [Rails Configuration Guide](https://guides.rubyonrails.org/configuring.html)
- `.ai/MEMORY.md` for project-specific conventions

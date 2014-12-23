# Halite

Write as a gem, release as a cookbook.

## Quick Start

Create a gem as per normal and add a dependency on `halite`. Add
`require 'halite/rake_tasks'` to your Rakefile. Run `rake build` and the
converted cookbook will be written to `pkg/`.

All Ruby code in the gem will be converted in to `libraries/` files. You can
add cookbook-specific files by add them to a `chef/` folder in the root of the
gem.

## Cookbook Dependencies

To add cookbook dependencies either add them to the gem requirements or use
the `halite_dependencies` metadata field:

```ruby
Gem::Specification.new do |spec|
  spec.requirements = %w{apache2 mysql}
  # or
  spec.metadata['halite_dependencies'] = 'php >= 2.0.0, chef-client'
end
```

Additionally if you gem depends on other Halite-based gems those will
automatically converted to cookbook dependencies.

## Cookbook Files

Any files under `chef/` in the gem will be written as is in to the cookbook.
For example you can add a recipe to your gem via `chef/recipes/default.rb`.

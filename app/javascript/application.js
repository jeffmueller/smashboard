// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"
import "push"
import { start as startOmarchyTheme } from "omarchy_theme"

// Per device; the cached palette is already painted by layouts/_omarchy_boot.
startOmarchyTheme()

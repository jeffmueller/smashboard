# frozen_string_literal: true

require 'rails_helper'

# A Stimulus target that the markup names but the controller never declares is
# silently `undefined` — the controller throws the first time it touches it, and
# nothing in Ruby-land notices. That's a class of bug no request spec can reach,
# so the wiring is checked directly.
RSpec.describe 'Stimulus target wiring' do
  let(:controllers) { Rails.root.glob('app/javascript/controllers/*_controller.js') }
  let(:views) { Rails.root.glob('app/views/**/*.erb') }

  # `static targets = ["a", "b"]`
  def declared_targets(path)
    list = path.read[/static\s+targets\s*=\s*\[(.*?)\]/m, 1]
    list.to_s.scan(/["']([^"']+)["']/).flatten
  end

  def controller_name(path)
    path.basename('.js').to_s.delete_suffix('_controller').tr('_', '-')
  end

  # Both spellings reach the DOM as data-<controller>-target: the attribute
  # written out longhand, and Rails' `data: { foo_target: "bar" }` hash.
  def used_targets
    views.each_with_object(Hash.new { |hash, key| hash[key] = Set.new }) do |view, used|
      source = view.read
      source.scan(/data-([a-z0-9-]+)-target=["']([^"']+)["']/) { |c, t| used[c] << t }
      source.scan(/([a-z0-9_]+)_target:\s*["']([^"']+)["']/) { |c, t| used[c.tr('_', '-')] << t }
    end
  end

  it 'declares every target the views ask for' do
    declared = controllers.to_h { |path| [controller_name(path), declared_targets(path)] }

    missing = used_targets.filter_map do |controller, targets|
      next unless declared.key?(controller)

      absent = targets.to_a - declared[controller]
      "#{controller}: #{absent.join(', ')}" if absent.any?
    end

    expect(missing).to be_empty, "targets used in views but never declared — #{missing.join('; ')}"
  end

  it 'names a controller that exists for every target attribute' do
    expect(used_targets.keys - controllers.map { |path| controller_name(path) }).to be_empty
  end
end

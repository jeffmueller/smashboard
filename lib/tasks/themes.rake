# frozen_string_literal: true

# Generates config/themes.yml from the Omarchy themes installed on this machine.
#
#   bin/rails themes:import
#
# The generated file is checked in and is the only thing the app reads at
# runtime — smashboard never looks at ~/.config/omarchy, so a deployment (or a
# user who has never heard of Omarchy) gets the same themes.
namespace :themes do
  THEME_DIRS = [
    '/usr/share/omarchy/themes',
    File.expand_path('~/.config/omarchy/themes')
  ].freeze

  # Omarchy names its background steps relative to a dark palette, and light
  # themes don't follow that naming consistently. Ordering by measured
  # luminance instead works for both.
  desc 'Import Omarchy themes into config/themes.yml'
  task import: :environment do
    themes = THEME_DIRS.flat_map { |dir| Dir.glob(File.join(dir, '*')) }
                       .select { |path| File.file?(File.join(path, 'colors.toml')) }
                       .to_h { |path| [File.basename(path), parse_palette(File.join(path, 'colors.toml'))] }
                       .compact
                       .sort.to_h

    built = themes.filter_map { |slug, palette| build_theme(slug, palette) }.to_h
    File.write(Rails.root.join('config/themes.yml'), header + built.to_yaml.sub(/\A---\n/, ''))
    File.write(Rails.root.join('app/assets/tailwind/themes.css'), stylesheet(built))

    report(built)
  end

  # --- Parsing --------------------------------------------------------------

  # colors.toml is flat `key = "value"`, so this needs no TOML library.
  def parse_palette(path)
    File.readlines(path).each_with_object({}) do |line, palette|
      # Keys include the ANSI palette (color0..color15), so digits are part of
      # a key name — `[a-z_]+` silently drops the entire ANSI fallback.
      next unless (match = line.match(/\A\s*([a-z_0-9]+)\s*=\s*"([^"]*)"/))

      palette[match[1]] = match[2]
    end
  end

  # Not every theme spells out four background steps — some carry a single
  # background plus an ANSI palette. Missing steps are derived rather than the
  # theme being dropped.
  ANSI = { 'danger' => 'color1', 'ok' => 'color2', 'warn' => 'color3',
           'accent' => 'color4', 'info' => 'color6' }.freeze

  def build_theme(slug, palette)
    light = palette['mode'] == 'light'
    backgrounds = steps(pick(palette, %w[darker_background dark_background background lighter_background]), light: light)
    foregrounds = pick(palette, %w[dark_foreground foreground light_foreground bright_foreground])
    return nil if backgrounds.empty? || foregrounds.empty?

    surfaces = order_by_luminance(backgrounds, light: light)
    canvas = surfaces[:canvas]

    [slug, {
      'name' => slug.tr('-', ' ').split.map(&:capitalize).join(' '),
      'mode' => light ? 'light' : 'dark',
      'tokens' => surfaces.transform_keys(&:to_s).merge(
        # Derived rather than taken from `selection`: a selection highlight is
        # meant to be loud, and some themes set it to a near-white blue that
        # makes a terrible hairline. Mixing surface toward the text is subtle in
        # every theme by construction.
        'line' => mix(surfaces[:surface], best_contrast(foregrounds, canvas), 0.14),
        'ink' => best_contrast(foregrounds, canvas),
        'ink-muted' => foregrounds.size > 1 ? mid_contrast(foregrounds, canvas) : mix(foregrounds.first, canvas, 0.3),
        'ink-faint' => palette['muted'].presence ||
                       (foregrounds.size > 2 ? least_contrast(foregrounds, canvas) : mix(foregrounds.first, canvas, 0.55)),
        'accent' => palette['accent'].presence || palette['blue'].presence || palette[ANSI['accent']],
        'ok' => palette['green'].presence || palette['bright_green'].presence || palette[ANSI['ok']],
        'warn' => palette['yellow'].presence || palette['orange'].presence || palette[ANSI['warn']],
        'danger' => palette['red'].presence || palette['bright_red'].presence || palette[ANSI['danger']],
        'info' => palette['cyan'].presence || palette['blue'].presence || palette[ANSI['info']]
      ).compact,
      'contrast' => contrast_ratio(best_contrast(foregrounds, canvas), canvas).round(2)
    }]
  end

  def pick(palette, keys)
    keys.filter_map { |key| palette[key].presence }.uniq
  end

  # Three distinct surface steps are needed; a theme that only declares one gets
  # the others mixed from it, away from the text so the relationship holds.
  def steps(backgrounds, light:)
    return backgrounds if backgrounds.size >= 3
    return [] if backgrounds.empty?

    base = backgrounds.max_by { |colour| light ? luminance(colour) : -luminance(colour) }
    toward = light ? '#000000' : '#ffffff'

    (backgrounds + [mix(base, toward, 0.05), mix(base, toward, 0.10)]).uniq
  end

  def mix(from, to, amount)
    blended = rgb(from).zip(rgb(to)).map { |a, b| ((a * (1 - amount)) + (b * amount)).round.clamp(0, 255) }

    format('#%<r>02x%<g>02x%<b>02x', r: blended[0], g: blended[1], b: blended[2])
  end

  # Dark themes want the page darker than the panels sitting on it. Light themes
  # want the opposite relationship for the same reason — panels should read as
  # raised — so the page takes the second-lightest step and the panels the
  # lightest, rather than panels receding into a brighter page.
  def order_by_luminance(colours, light:)
    sorted = colours.sort_by { |colour| luminance(colour) }

    if light
      sorted = sorted.reverse
      { canvas: sorted[1] || sorted[0], surface: sorted[0], raised: sorted[2] || sorted[1] || sorted[0] }
    else
      { canvas: sorted[0], surface: sorted[1] || sorted[0], raised: sorted[2] || sorted[1] || sorted[0] }
    end
  end

  def best_contrast(colours, background)
    colours.max_by { |colour| contrast_ratio(colour, background) }
  end

  def least_contrast(colours, background)
    colours.min_by { |colour| contrast_ratio(colour, background) }
  end

  def mid_contrast(colours, background)
    ranked = colours.sort_by { |colour| contrast_ratio(colour, background) }
    ranked[ranked.length / 2] || ranked.last
  end

  # --- Colour maths ---------------------------------------------------------

  def rgb(hex)
    hex.to_s.delete('#').scan(/../).map { |pair| pair.to_i(16) }
  end

  def luminance(hex)
    rgb(hex).map { |channel|
      value = channel / 255.0
      value <= 0.03928 ? value / 12.92 : (((value + 0.055) / 1.055)**2.4)
    }.then { |r, g, b| (0.2126 * r) + (0.7152 * g) + (0.0722 * b) }
  end

  def contrast_ratio(foreground, background)
    lighter, darker = [luminance(foreground), luminance(background)].minmax.reverse
    (lighter + 0.05) / (darker + 0.05)
  end

  # One stylesheet holding every theme as a block of custom properties. Switching
  # is then a single attribute change on <html> — no reload, no flash, no
  # per-theme request.
  def stylesheet(themes)
    dark = themes[Theme::SYSTEM_DARK] || themes.values.find { |t| t['mode'] == 'dark' }
    light = themes[Theme::SYSTEM_LIGHT] || themes.values.find { |t| t['mode'] == 'light' }

    <<~CSS
      /* Generated by `bin/rails themes:import`. Do not hand-edit. */

      /* No explicit choice: follow the operating system. */
      :root {
      #{declarations(dark)}
      }

      @media (prefers-color-scheme: light) {
        /* :not([data-theme]) keeps an explicit choice winning over the OS. */
        :root:not([data-theme]) {
      #{declarations(light, indent: 4)}
        }
      }

      #{themes.map { |slug, theme| block(slug, theme) }.join("\n")}
    CSS
  end

  def block(slug, theme)
    "[data-theme=\"#{slug}\"] {\n#{declarations(theme)}\n}\n"
  end

  def declarations(theme, indent: 2)
    theme['tokens'].map { |token, value| "#{' ' * indent}--sb-#{token}: #{value};" }.join("\n")
  end

  def header
    <<~YAML
      # Generated by `bin/rails themes:import` from the Omarchy themes installed
      # on the machine that ran it. Checked in on purpose: this file is the only
      # thing the app reads at runtime, so themes work anywhere.
      #
      # Do not hand-edit — rerun the task instead.
    YAML
  end

  def report(themes)
    puts "Wrote #{themes.size} themes to config/themes.yml"
    modes = themes.values.group_by { |theme| theme['mode'] }.transform_values(&:size)
    puts "  #{modes.map { |mode, count| "#{count} #{mode}" }.join(', ')}"

    # WCAG AA for body text is 4.5:1; anything under that is worth knowing about.
    poor = themes.select { |_, theme| theme['contrast'] < 4.5 }
    puts poor.any? ? "  below AA contrast: #{poor.keys.join(', ')}" : '  every theme clears 4.5:1 body contrast'
  end
end

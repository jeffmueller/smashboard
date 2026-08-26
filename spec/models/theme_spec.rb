# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Theme do
  it 'loads the generated themes' do
    expect(described_class.all).to be_present
    expect(described_class.all).to all(be_a(described_class))
  end

  it 'finds a theme by slug' do
    theme = described_class.find(described_class::SYSTEM_DARK)

    expect(theme.slug).to eq(described_class::SYSTEM_DARK)
    expect(theme).to be_dark
  end

  it 'returns nothing for an unknown slug' do
    expect(described_class.find('not-a-theme')).to be_nil
  end

  it 'ships both dark and light themes' do
    expect(described_class.dark).to be_present
    expect(described_class.light).to be_present
  end

  # The system defaults are named in the stylesheet's prefers-color-scheme
  # block, so they have to exist and be the mode they claim.
  it 'has a real theme behind each system default' do
    expect(described_class.find(described_class::SYSTEM_DARK)).to be_dark
    expect(described_class.find(described_class::SYSTEM_LIGHT)).not_to be_dark
  end

  describe '.attribute_for' do
    it 'renders no attribute when following the system' do
      expect(described_class.attribute_for(nil)).to be_nil
      expect(described_class.attribute_for('')).to be_nil
      expect(described_class.attribute_for(described_class::SYSTEM)).to be_nil
    end

    it 'renders the slug for an explicit choice' do
      expect(described_class.attribute_for('tokyo-night')).to eq('tokyo-night')
    end

    it 'renders nothing for a slug that does not exist' do
      expect(described_class.attribute_for('not-a-theme')).to be_nil
    end
  end

  it 'has a fallback with a complete token set, for a broken themes.yml' do
    expect(described_class::TOKENS.all? { |t| described_class.fallback.token(t).present? }).to be(true)
  end

  describe 'the generated data' do
    it 'gives every theme a complete token set' do
      incomplete = described_class.all.reject { |theme| described_class::TOKENS.all? { |t| theme.token(t).present? } }

      expect(incomplete.map(&:slug)).to be_empty
    end

    it 'uses hex colours throughout' do
      values = described_class.all.flat_map { |theme| theme.tokens.values }

      expect(values).to all(match(/\A#[0-9a-f]{6}\z/i))
    end

    # Body text has to clear WCAG AA against its own canvas in every theme, or
    # picking one would be a trap.
    it 'clears 4.5:1 body contrast everywhere' do
      failing = described_class.all.select { |theme| theme.contrast < 4.5 }

      expect(failing.map { |theme| [theme.slug, theme.contrast] }).to be_empty
    end

    it 'separates canvas from surface so panels read as raised' do
      flat = described_class.all.select { |theme| theme.token('canvas') == theme.token('surface') }

      expect(flat.map(&:slug)).to be_empty
    end
  end
end

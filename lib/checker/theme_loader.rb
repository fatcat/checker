# frozen_string_literal: true

require 'json'

module Checker
  class ThemeLoader
    MAX_THEMES = 50
    REQUIRED_COLORS = %w[
      background surface surface-hover border
      text text-muted accent accent-hover
      success warning danger info
    ].freeze

    class << self
      def themes_dir
        @themes_dir ||= File.join(Dir.pwd, 'themes')
      end

      def load_all
        return @themes if @themes

        @themes = {}
        theme_files = Dir.glob(File.join(themes_dir, '*.json')).first(MAX_THEMES)

        theme_files.each do |file|
          theme = load_theme_file(file)
          @themes[theme['id']] = theme if theme
        end

        # Ensure we have at least the default theme
        ensure_default_theme

        @themes
      end

      def reload!
        @themes = nil
        load_all
      end

      def get(theme_id)
        load_all[theme_id] || load_all['dark-default']
      end

      def all_themes
        load_all.values.sort_by { |t| [t['type'] == 'dark' ? 0 : 1, t['name']] }
      end

      def dark_themes
        all_themes.select { |t| t['type'] == 'dark' }
      end

      def light_themes
        all_themes.select { |t| t['type'] == 'light' }
      end

      def theme_css_vars(theme_id)
        theme = get(theme_id)
        return '' unless theme

        vars = theme['colors'].map do |key, value|
          "--color-#{key}: #{value};"
        end

        ":root { #{vars.join(' ')} }"
      end

      private

      def load_theme_file(file)
        content = File.read(file)
        theme = JSON.parse(content)

        return nil unless valid_theme?(theme, file)

        theme
      rescue JSON::ParserError => e
        Checker.logger.warn "Invalid JSON in theme file #{file}: #{e.message}"
        nil
      rescue StandardError => e
        Checker.logger.warn "Error loading theme file #{file}: #{e.message}"
        nil
      end

      def valid_theme?(theme, file)
        # Check required fields
        unless theme['id'] && theme['name'] && theme['type'] && theme['colors']
          Checker.logger.warn "Theme file #{file} missing required fields (id, name, type, colors)"
          return false
        end

        # Check type is valid
        unless %w[dark light].include?(theme['type'])
          Checker.logger.warn "Theme file #{file} has invalid type (must be 'dark' or 'light')"
          return false
        end

        # Check all required colors are present
        missing_colors = REQUIRED_COLORS - theme['colors'].keys
        if missing_colors.any?
          Checker.logger.warn "Theme file #{file} missing colors: #{missing_colors.join(', ')}"
          return false
        end

        # Validate color formats (basic hex check)
        invalid_colors = theme['colors'].reject do |_key, value|
          value.match?(/^#[0-9a-fA-F]{3,8}$/)
        end

        if invalid_colors.any?
          Checker.logger.warn "Theme file #{file} has invalid color values: #{invalid_colors.keys.join(', ')}"
          return false
        end

        true
      end

      def ensure_default_theme
        return if @themes['dark-default']

        # Fallback default theme if file is missing
        @themes['dark-default'] = {
          'id' => 'dark-default',
          'name' => 'Dark (Default)',
          'type' => 'dark',
          'description' => 'The default dark theme',
          'colors' => {
            'background' => '#0a0a0a',
            'surface' => '#1a1a1a',
            'surface-hover' => '#252525',
            'border' => '#333333',
            'text' => '#e0e0e0',
            'text-muted' => '#808080',
            'accent' => '#00bf63',
            'accent-hover' => '#00a354',
            'success' => '#00bf63',
            'warning' => '#ffc107',
            'danger' => '#dc3545',
            'info' => '#17a2b8'
          }
        }
      end
    end
  end
end

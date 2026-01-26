# frozen_string_literal: true

module Checker
  class App
    # Get all settings
    get '/api/settings' do
      json settings: Configuration.all
    end

    # Update settings
    put '/api/settings' do
      data = json_body

      data.each do |key, value|
        Configuration.set(key, value)
      end

      # Reconfigure logger if logging settings changed
      if data['log_rotation_period'] || data['log_retention_count']
        Checker.reconfigure_logger
      end

      json settings: Configuration.all
    end

    # Get available themes
    get '/api/themes' do
      themes = ThemeLoader.all_themes.map do |theme|
        {
          id: theme['id'],
          name: theme['name'],
          type: theme['type'],
          description: theme['description']
        }
      end

      json(
        themes: themes,
        dark_themes: ThemeLoader.dark_themes.map { |t| { id: t['id'], name: t['name'] } },
        light_themes: ThemeLoader.light_themes.map { |t| { id: t['id'], name: t['name'] } }
      )
    end

    # Get CSS variables for a specific theme
    get '/api/themes/:id/css' do
      content_type 'text/css'
      ThemeLoader.theme_css_vars(params[:id])
    end

    # Settings page
    get '/settings' do
      erb :settings
    end
  end
end

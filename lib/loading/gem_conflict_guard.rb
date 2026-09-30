# frozen_string_literal: true

module Narou
  module GemConflictGuard
    module_function

    def remove_installed_gem!(gem_name, load_path: $LOAD_PATH, loaded_features: $LOADED_FEATURES, loaded_specs: nil)
      installed_gem_path = lambda do |path|
        normalized_path = path.to_s.tr("\\", "/")
        normalized_path.match?(%r{(?:\A|/)gems/#{Regexp.escape(gem_name)}-[^/]+(?:/|\z)})
      end

      load_path.reject!(&installed_gem_path)
      loaded_features.reject!(&installed_gem_path)
      loaded_specs ||= Gem.loaded_specs if defined?(Gem)
      loaded_specs&.delete(gem_name)
    end
  end
end

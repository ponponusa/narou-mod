# frozen_string_literal: true

require "lib/loading/gem_conflict_guard"

RSpec.describe Narou::GemConflictGuard do
  describe ".remove_installed_gem!" do
    let(:installed_gem_root) { "/opt/ruby/gems/3.4.0/gems/narou-mod-3.1.7" }
    let(:installed_load_path) { "#{installed_gem_root}/lib" }
    let(:installed_feature) { "#{installed_load_path}/core/narou.rb" }
    let(:vendored_load_path) do
      "/workspace/narou-mod/vendor/bundle/ruby/3.4.0/gems/memoist-0.16.2/lib"
    end
    let(:vendored_feature) { "#{vendored_load_path}/memoist.rb" }
    let(:repository_load_path) { "/workspace/narou-mod/lib" }
    let(:specification) { instance_double(Gem::Specification) }
    let(:memoist_specification) { instance_double(Gem::Specification) }
    let(:load_path) { [installed_load_path, vendored_load_path, repository_load_path] }
    let(:loaded_features) { [installed_feature, vendored_feature] }
    let(:loaded_specs) do
      {
        "narou-mod" => specification,
        "memoist" => memoist_specification
      }
    end

    it "removes only paths owned by the installed narou-mod gem" do
      described_class.remove_installed_gem!(
        "narou-mod",
        load_path: load_path,
        loaded_features: loaded_features,
        loaded_specs: loaded_specs
      )

      expect(load_path).to eq [vendored_load_path, repository_load_path]
      expect(loaded_features).to eq [vendored_feature]
      expect(loaded_specs).to eq("memoist" => memoist_specification)
    end

    it "removes installed gem paths even when the gem is not loaded" do
      described_class.remove_installed_gem!(
        "narou-mod",
        load_path: load_path,
        loaded_features: loaded_features,
        loaded_specs: {}
      )

      expect(load_path).to eq [vendored_load_path, repository_load_path]
      expect(loaded_features).to eq [vendored_feature]
    end
  end
end

# frozen_string_literal: true

#
# Copyright 2013 whiteleaf. All rights reserved.
#

module Narou
  VERSION = "3.1.10".freeze

  commit_path = File.expand_path("../../commitversion", __dir__)
  commit_value = if File.exist?(commit_path)
                   content = File.read(commit_path).strip
                   content.empty? ? nil : content
                 end
  COMMIT = commit_value&.freeze
end

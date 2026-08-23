#!/usr/bin/env ruby
# frozen_string_literal: true

root = File.expand_path("..", __dir__)
failures = []
Dir.glob(File.join(root, "**", "*.md")).each do |file|
  next if file.include?("/.build/")

  File.read(file).scan(/\[[^\]]*\]\(([^)]+)\)/).flatten.each do |target|
    next if target.start_with?("http://", "https://", "mailto:", "#")

    path = target.split("#", 2).first
    next if path.nil? || path.empty?

    resolved = File.expand_path(path, File.dirname(file))
    failures << "#{file.delete_prefix(root + "/")}: missing #{target}" unless File.exist?(resolved)
  end
end

if failures.any?
  warn failures.join("\n")
  exit 1
end

puts "Local documentation links passed."

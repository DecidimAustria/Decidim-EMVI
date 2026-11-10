# Apply the upstream Rails 8.1.4.1 policy to Rails 7 and MiniMagick 4 subprocesses.
# ImageMagick combines this policy with its system policy.
policy_directory = Rails.root.join("config", "image_magick").to_s
ENV["MAGICK_CONFIGURE_PATH"] = [policy_directory, ENV["MAGICK_CONFIGURE_PATH"]].compact.reject(&:empty?).join(File::PATH_SEPARATOR)

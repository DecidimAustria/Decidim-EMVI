# frozen_string_literal: true

# Rails 7.0 changed the default key derivation from SHA1 to SHA256. Accept
# cookies issued with our former 6.1 defaults while writing new SHA256 cookies.
# The deployment must keep the existing SECRET_KEY_BASE.
Rails.application.config.after_initialize do |app|
  generator = ActiveSupport::KeyGenerator.new(
    app.secret_key_base,
    iterations: 1000,
    hash_digest_class: OpenSSL::Digest::SHA1
  )
  dispatch = app.config.action_dispatch
  encrypted_key = generator.generate_key(dispatch.authenticated_encrypted_cookie_salt, ActiveSupport::MessageEncryptor.key_len("aes-256-gcm"))
  signed_key = generator.generate_key(dispatch.signed_cookie_salt)
  dispatch.cookies_rotations.rotate :encrypted, encrypted_key, cipher: "aes-256-gcm"
  dispatch.cookies_rotations.rotate :signed, signed_key
end

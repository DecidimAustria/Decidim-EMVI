module ApplicationHelper
  include Decidim::ApplicationHelper
  include Decidim::TranslationsHelper
  include Decidim::ResourceHelper

  # Public: truncates the post body
  #
  # post - a Decidim::Blog instance
  # max_length - a number to limit the length of the body
  #
  # Returns the post's body truncated.
  def post_description_with_read_more(post,  max_length = 600)
    link = post_path(post)
    body = translated_attribute(post.body)
    tail = "... <br/> #{link_to(t("read_more", scope: "decidim.blogs"), link, class: "button__posts button small hollow")}".html_safe
    CGI.unescapeHTML html_truncate(body, max_length: max_length, tail: tail)
  end

  def direction_attribute
    rtl_locales = %w(ar-SA fa-IR)
    rtl_locales.include?(I18n.locale.to_s) ? "rtl" : "ltr"
  end
end

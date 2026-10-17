# frozen_string_literal: true

# Generate /api/docs from the installed schema during the image build.
Rake::Task["assets:precompile"].enhance(["decidim_api:generate_docs"])

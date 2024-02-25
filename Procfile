web: bundle exec rails server -p $PORT
worker: bundle exec good_job --max-threads=5
release: bundle exec rake db:migrate

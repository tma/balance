# Production Procfile for Heroku/Render/Railway
web: bundle exec thrust ./bin/rails server
worker: ./bin/rails solid_queue:work
release: ./bin/rails db:migrate

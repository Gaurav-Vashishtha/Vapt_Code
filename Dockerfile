FROM ruby:3.2.6-slim

# Install system dependencies
RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends \
      build-essential libpq-dev git curl nodejs && \
    rm -rf /var/lib/apt/lists/*

# Set environment variables
ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development test"

WORKDIR /rails

# Install gems
COPY Gemfile Gemfile.lock ./
RUN bundle install --frozen

# Copy code. Explicit paths rather than `COPY . .`: the build context holds
# scratch directories, local tooling and developer files that have no business
# in a production image, and a recursive copy silently picks up whatever is
# added to the repo later. .dockerignore still applies as a second line of
# defence for secrets.
COPY Rakefile config.ru .browserslistrc babel.config.js postcss.config.js package.json yarn.lock ./
COPY app app
COPY bin bin
COPY config config
COPY db db
COPY lib lib
COPY public public
COPY vendor vendor
COPY node_modules node_modules

# Precompile assets
RUN SECRET_KEY_BASE_DUMMY=1 bundle exec rails assets:precompile

# Entrypoint for migrations
COPY bin/docker-entrypoint /usr/bin/
RUN chmod +x /usr/bin/docker-entrypoint
ENTRYPOINT ["docker-entrypoint"]

EXPOSE 3000
CMD ["./bin/rails", "server", "-b", "0.0.0.0"]
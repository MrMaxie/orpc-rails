FROM ruby:3.4-bookworm@sha256:80259ba83f866aaa43c689e11569dc950b2e508effca0799d50608f7c4ca6172
WORKDIR /suite
COPY Gemfile Gemfile.lock ./
RUN bundle install --jobs 4
COPY run.rb orpc-rails.gem ./
COPY test ./test
COPY orpc-rails.gemspec LICENSE README.md CHANGELOG.md ./distribution/
CMD ["bundle", "exec", "ruby", "run.rb"]

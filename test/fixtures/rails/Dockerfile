ARG RUBY_IMAGE
FROM ${RUBY_IMAGE}
WORKDIR /fixture
COPY Gemfile Gemfile.lock ./
RUN bundle install --jobs 4
COPY app.rb ./
CMD ["sleep", "infinity"]

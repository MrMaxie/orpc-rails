ARG RUBY_IMAGE
FROM ${RUBY_IMAGE}
WORKDIR /fixture
COPY Gemfile Gemfile.lock ./
RUN bundle install --jobs 4
COPY app.rb tasks_test.rb rpc_prerequisites_test.rb ./
CMD ["sleep", "infinity"]

# frozen_string_literal: true

module OrpcRails
  # Store names, not controller instances, so Rails reloads do not retain classes.
  class Registry
    def initialize
      @controllers = []
      @mutex = Mutex.new
    end

    def register(controller)
      name = controller.name
      raise ArgumentError, "Contract controllers must have a constant name" unless name

      @mutex.synchronize { @controllers |= [name.dup.freeze] }
    end

    def controller(name)
      registered = @mutex.synchronize { @controllers.include?(name) }
      registered ? resolve(name) : nil
    end

    def endpoints
      names = @mutex.synchronize { @controllers.dup }
      names.flat_map do |name|
        controller = resolve(name)
        controller.respond_to?(:orpc_contracts) ? controller.orpc_contracts : []
      end.freeze
    end

    private

    def resolve(name)
      Object.const_get(name)
    rescue NameError
      nil
    end
  end
end

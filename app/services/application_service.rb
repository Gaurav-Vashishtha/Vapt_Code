class ApplicationService
  # Support both positional and keyword arguments (Ruby 3 keyword semantics).
  def self.call(*args, **kwargs, &block)
    new(*args, **kwargs, &block).call
  end
end

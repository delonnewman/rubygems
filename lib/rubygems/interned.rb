class Gem::Interned
  class << self
    alias_method :realnew, :new
  end

  def self.new *args
    (@interned ||= Hash.new { |h, k| h[k] = realnew(*k) })[args]
  end
end

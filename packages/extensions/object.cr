class Object
  def pipe
    yield self
  end

  def or(other : T) : T | self forall T
    self || other
  end
end

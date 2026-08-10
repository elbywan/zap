require "spec"
require "../pool"

describe Concurrency::Pool, tags: {"utils", "utils.concurrency"} do
  it "creates objects up to capacity and reuses them afterwards" do
    created = Atomic(Int32).new(0)
    pool = Concurrency::Pool(Int32).new(2) { created.add(1) }

    a = pool.get
    b = pool.get
    created.get.should eq(2)

    pool.release(a)
    c = pool.get
    # The object is reused, no new object is created
    created.get.should eq(2)
    c.should eq(a)

    pool.release(b)
    pool.release(c)
  end

  it "works with a capacity of 1" do
    created = Atomic(Int32).new(0)
    pool = Concurrency::Pool(Int32).new(1) { created.add(1); 1 }

    # Regression test: exactly one object is created, the second get reuses it
    pool.get.should eq(1)
    created.get.should eq(1)
  end
end

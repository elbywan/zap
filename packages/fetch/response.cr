# The response surface shared by the fetch transports: the status, the
# headers, and the body, regardless of the underlying protocol client.
record FetchResponse, headers : HTTP::Headers, body : IO

# The status check shared by the fetch transports: raises on a non-200
# status, and raises an IO::Error for the transient statuses (429 and
# 5xx) so the client retry loop re-attempts them like a dropped
# connection.
def fetch_check_status(url : String, status : Int32) : Nil
  return if status == 200
  if status == 429 || status >= 500
    raise IO::Error.new("Invalid status code from #{url} (#{status})")
  end
  raise "Invalid status code from #{url} (#{status})"
end

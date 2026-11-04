class ZabbixApi
  # Base class of every error the gem raises, carrying the server's own answer beside the
  # message text.
  #
  # {#error_message} is the server's `message` and `data` joined, {#error} the whole JSON-RPC
  # error object, {#response} the parsed body they came from.
  # In an {ApiError} carrying a server's error, each secret the request carried
  # ({Client::SECRET_KEYS}, a macro value sent with type 1, and the body `auth`) reads '***'
  # wherever the answer quoted it.
  #
  # All three are nil for a {TransportError} and for an error the gem raises locally. An
  # {HttpError} carries the `Net::HTTPResponse` as {#response}, with {#error} and
  # {#error_message} nil.
  class BaseError < RuntimeError
    # @!attribute [rw] response
    #   @return [Hash, Net::HTTPResponse, nil] the parsed response body, or the HTTP response of an {HttpError}
    # @!attribute [rw] error
    #   @return [Hash, nil] the JSON-RPC error object, with `code`, `message` and `data`
    # @!attribute [rw] error_message
    #   @return [String, nil] the server's reason as `"<message>: <data>"`
    attr_accessor :response, :error, :error_message

    # @param message [String] the exception message the caller built
    # @param response [Hash, Net::HTTPResponse, nil] the parsed response body, or the HTTP response of an {HttpError}
    def initialize(message, response = nil)
      super(message)
      @response = response

      set_error! if @response
    end

  private

    def set_error!
      @error = @response['error']
      @error_message = "#{@error['message']}: #{@error['data']}"
    rescue StandardError
      @error = nil
      @error_message = nil
    end
  end

  # Raised for a JSON-RPC error in the server's answer, and for a call the gem refuses locally.
  class ApiError < BaseError
  end

  # Raised when the server answers with an HTTP status other than 200.
  class HttpError < BaseError
  end

  # Raised when no JSON-RPC exchange took place: the connection was refused, the name did not
  # resolve, TLS failed, a timeout expired, the url did not parse, or the answer was not JSON.
  #
  # `response` is nil; the original exception is kept as `cause`.
  class TransportError < BaseError
  end
end

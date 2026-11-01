# frozen_string_literal: true

module PaySafe
  # Client for one PaySafe project in one environment. Thread-safe.
  class Client
    DEFAULT_BASE_URL = "https://api.paysafe.co.tz"
    DEFAULT_TIMEOUT = 30
    DEFAULT_MAX_RETRIES = 4
    MAX_RESPONSE_BYTES = 16 * 1024 * 1024
    INITIAL_BACKOFF = 0.5
    MAX_BACKOFF = 8.0
    IN_PROGRESS_SLEEP = 1.0
    METHODS = { "GET" => Net::HTTP::Get, "POST" => Net::HTTP::Post, "PATCH" => Net::HTTP::Patch, "DELETE" => Net::HTTP::Delete }.freeze

    attr_reader :environment, :payments, :payment_links, :control_numbers, :refunds, :balance, :customers, :transfers,
                :webhook_endpoints, :events

    # api_key defaults to PAYSAFE_SECRET_KEY, base_url to PAYSAFE_BASE_URL. timeout is per attempt in seconds;
    # max_retries counts retries after the first attempt. logger receives a LogRecord per attempt (never the key or bodies).
    # sleeper and random are test hooks.
    def initialize(api_key: nil, base_url: nil, timeout: DEFAULT_TIMEOUT, max_retries: DEFAULT_MAX_RETRIES, api_version: nil,
                   logger: nil, user_agent_suffix: nil, allow_insecure_http: false, sleeper: ->(s) { sleep(s) }, random: -> { Random.rand })
      key = api_key || ENV.fetch("PAYSAFE_SECRET_KEY", nil)
      raise ConfigurationError, "No API key given and PAYSAFE_SECRET_KEY is not set" if key.nil? || key.empty?
      raise ConfigurationError, "API key contains invalid characters" unless Validate::API_KEY.match?(key)

      @environment = if key.start_with?("paysafe_test_") then :test
                     elsif key.start_with?("paysafe_live_") then :live
                     else raise ConfigurationError, "API key must start with paysafe_test_ or paysafe_live_"
                     end
      @api_key = key
      @base_url = resolve_base_url(base_url, allow_insecure_http)
      raise ConfigurationError, "timeout must be positive" unless timeout.is_a?(Numeric) && timeout.positive?
      raise ConfigurationError, "max_retries must be zero or more" unless max_retries.is_a?(Integer) && max_retries >= 0
      raise ConfigurationError, "user_agent_suffix contains control characters" if user_agent_suffix && Validate.control?(user_agent_suffix, false)

      @timeout = timeout
      @max_retries = max_retries
      @api_version = api_version
      @logger = logger
      @sleeper = sleeper
      @random = random
      @user_agent = "paysafe-ruby/#{VERSION} (Ruby #{RUBY_VERSION}; #{RUBY_PLATFORM})#{" #{user_agent_suffix}" if user_agent_suffix}"
      @payments = Resources::Payments.new(self)
      @payment_links = Resources::PaymentLinks.new(self)
      @control_numbers = Resources::ControlNumbers.new(self)
      @refunds = Resources::Refunds.new(self)
      @balance = Resources::Balance.new(self)
      @customers = Resources::Customers.new(self)
      @transfers = Resources::Transfers.new(self)
      @webhook_endpoints = Resources::WebhookEndpoints.new(self)
      @events = Resources::Events.new(self)
    end

    def inspect
      "#<PaySafe::Client environment=#{@environment} base_url=#{@base_url}>"
    end

    # Low-level escape hatch: any method and path under /v1 with the raw ApiResponse.
    def request(method, path, query: {}, body: nil, **opts)
      send_request(method.to_s.upcase, "/#{path.to_s.delete_prefix("/")}", query, body, opts)
    end

    # Sleeper used by the polling helpers.
    def pause(seconds)
      @sleeper.call(seconds)
    end

    def send_request(method, path, query, body, opts)
      options = RequestOptions.from(opts)
      raise InvalidRequestError, "Unsupported HTTP method #{method}" unless METHODS.key?(method)

      target = "#{@base_url}#{path}"
      first = true
      query.each do |k, v|
        next if v.nil?

        k = k.to_s
        v = v.to_s
        Validate.query_value(k, v)
        target << (first ? "?" : "&") << Util.encode(k) << "=" << Util.encode(v)
        first = false
      end
      Validate.body_size(body) if body
      retryable = %w[GET DELETE PATCH].include?(method) || !options.idempotency_key.nil?
      max_attempts = 1 + (options.max_retries || @max_retries)
      attempt = 0
      loop do
        attempt += 1
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        begin
          response = send_once(method, target, body, options)
        rescue ApiConnectionError => e
          log(method, path, nil, attempt, started, nil, e.message)
          raise if !retryable || attempt >= max_attempts || e.is_a?(ResponseTooLargeError)

          @sleeper.call(backoff(attempt))
          next
        end
        log(method, path, response.status, attempt, started, response.request_id, nil)
        return response if response.status < 300
        if response.status < 400
          raise ApiError.new(status: response.status, code: "unexpected_redirect",
                             message: "The API answered with a redirect, which this SDK never follows",
                             request_id: response.request_id, headers: response.headers)
        end

        error = ErrorMapper.from_response(response)
        delay = retry_delay(error, retryable, attempt)
        raise error if delay.nil? || attempt >= max_attempts

        @sleeper.call(delay)
      end
    end

    private

    def resolve_base_url(base_url, allow_insecure_http)
      url = base_url || ENV.fetch("PAYSAFE_BASE_URL", nil)
      url = DEFAULT_BASE_URL if url.nil? || url.empty?
      raise ConfigurationError, "base_url contains whitespace or control characters" if url.match?(/\s/) || Validate.control?(url, false)

      url = url.sub(%r{/+\z}, "").delete_suffix("/v1")
      parsed = begin
        URI.parse(url)
      rescue URI::InvalidURIError
        raise ConfigurationError, "base_url must be an absolute URL"
      end
      if !parsed.is_a?(URI::HTTP) || parsed.host.nil? || parsed.userinfo || parsed.query || parsed.fragment
        raise ConfigurationError, "base_url must be an absolute URL without credentials, query or fragment"
      end
      unless parsed.scheme == "https" || (parsed.scheme == "http" && (allow_insecure_http || Validate.loopback?(parsed.host)))
        raise ConfigurationError, "base_url must use https (plain http is only allowed for localhost or with allow_insecure_http)"
      end

      url
    end

    def retry_delay(error, retryable, attempt)
      return IN_PROGRESS_SLEEP if error.code == "idempotency_in_progress"
      return error.retry_after ? error.retry_after.to_f : backoff(attempt) if [429, 503].include?(error.status)
      return backoff(attempt) if error.status >= 500 && error.code != "provider_error" && retryable

      nil
    end

    def backoff(attempt)
      ceiling = [MAX_BACKOFF, INITIAL_BACKOFF * (2**[attempt - 1, 20].min)].min
      @random.call * ceiling
    end

    def send_once(method, target, body, options)
      uri = URI.parse(target)
      req = METHODS[method].new(uri.request_uri)
      req["Authorization"] = "Bearer #{@api_key}"
      req["Accept"] = "application/json"
      req["User-Agent"] = @user_agent
      req["PaySafe-Version"] = @api_version if @api_version
      req["Idempotency-Key"] = options.idempotency_key if options.idempotency_key
      req["X-Request-ID"] = options.request_id if options.request_id
      options.headers.each { |k, v| req[k] = v }
      if body
        req.body = body
        req["Content-Type"] = "application/json"
      end
      timeout = options.timeout || @timeout
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.verify_mode = OpenSSL::SSL::VERIFY_PEER
      http.open_timeout = [timeout, 10].min
      http.read_timeout = timeout
      http.write_timeout = timeout
      begin
        http.start { |conn| read_response(conn, req, options) }
      rescue Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout => e
        raise ApiTimeoutError, "Request to PaySafe timed out: #{e.class.name.split("::").last}"
      rescue ResponseTooLargeError
        raise
      rescue SocketError, SystemCallError, OpenSSL::SSL::SSLError, IOError, Timeout::Error => e
        raise ApiConnectionError, "Could not reach PaySafe: #{e.message}"
      end
    end

    def read_response(conn, req, options)
      result = nil
      conn.request(req) do |res|
        length = res["content-length"]
        raise ResponseTooLargeError if length && length.to_i > MAX_RESPONSE_BYTES

        body = +""
        res.read_body do |chunk|
          body << chunk
          raise ResponseTooLargeError if body.bytesize > MAX_RESPONSE_BYTES
        end
        headers = res.to_hash.to_h { |k, v| [k.downcase, v.join(", ")] }
        result = ApiResponse.new(res.code.to_i, headers, body.force_encoding(Encoding::UTF_8), options.idempotency_key)
      end
      result
    end

    def log(method, path, status, attempt, started, request_id, error)
      return unless @logger

      duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
      @logger.call(LogRecord.new(http_method: method, path: path, status: status, attempt: attempt, duration: duration, request_id: request_id,
                                 error: error))
    end
  end
end

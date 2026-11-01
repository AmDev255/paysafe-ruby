# frozen_string_literal: true

module Support
  TEST_KEY = "paysafe_test_9f2Kx7Qm3Rt8Vw2Yz5Ab1Cd4Ef6Gh9Jk"
  REQUEST_ID = "req_01J7A9Q0K3M4N5P6R7S8T9V0W1"
  BASE = "https://api.test.invalid"
  FIXTURES = File.expand_path("../tests/fixtures", __dir__)

  module_function

  def fixture(name)
    JSON.parse(File.read(File.join(FIXTURES, "#{name}.json")))
  end

  # The first 2xx response of an operation fixture: [status, body, headers].
  def success_of(fixture)
    code = fixture["responses"].keys.find { |k| k.start_with?("2") }
    r = fixture["responses"][code]
    [code.to_i, r["body"], r["headers"] || {}]
  end

  def header(request, name)
    request.headers.find { |k, _| k.casecmp?(name) }&.last
  end

  class Harness
    attr_reader :client, :requests, :sleeps

    def initialize(max_retries: 4, timeout: 30, **options)
      @requests = []
      @sleeps = []
      @first = true
      @client = PaySafe::Client.new(api_key: TEST_KEY, base_url: BASE, max_retries: max_retries, timeout: timeout,
                                    sleeper: ->(s) { @sleeps << s }, random: -> { 0.5 }, **options)
      @stub = WebMock.stub_request(:any, /api\.test\.invalid/).with { |req| @requests << req }
    end

    def request_count
      @requests.size
    end

    def total_sleep
      @sleeps.sum
    end

    def enqueue_json(status, body, headers = {})
      all = { "Content-Type" => "application/json", "X-Request-ID" => REQUEST_ID }
      all.delete("Content-Type") if body.nil?
      all.merge!(headers)
      enqueue_response(status: status, body: body.nil? ? "" : JSON.generate(body), headers: all)
    end

    def enqueue_raw(status, body, headers = {})
      enqueue_response(status: status, body: body, headers: { "X-Request-ID" => REQUEST_ID }.merge(headers))
    end

    def enqueue_disconnect
      chain.to_raise(Errno::ECONNRESET)
      self
    end

    def enqueue_hang
      chain.to_timeout
      self
    end

    def enqueue_response(**response)
      chain.to_return(**response)
      self
    end

    private

    def chain
      if @first
        @first = false
        @stub
      else
        @stub.then
      end
    end
  end
end

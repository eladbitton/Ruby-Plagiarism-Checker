require 'json'
require 'net/http'
require 'mimemagic'
require 'mimemagic/overlay'
require 'openssl'

module CopyleaksApi
  class Api
    BASE_URL = 'https://api.copyleaks.com'.freeze
    API_VERSION = 'v1'.freeze

    # constructor
    def initialize
      uri = URI(BASE_URL)
      @http = Net::HTTP.new(uri.host, uri.port)
      @http.use_ssl = true
      @http.verify_mode = ::OpenSSL::SSL::VERIFY_NONE
    end

    # make get request without any callback header
    def get(path, options = {})
      request = Net::HTTP::Get.new(request_uri(path))
      make_request(request, options.merge(no_callbacks: true))
    end

    # make post request with given options
    def post(path, body = nil, options = {})
      request = Net::HTTP::Post.new(request_uri(path))
      request.body = body
      make_request(request, options)
    end

    # makes delete request without callbacks
    def delete(path, options = {})
      request = Net::HTTP::Delete.new(request_uri(path))
      make_request(request, options.merge(no_callbacks: true))
    end

    # makes post request with file inside
    def post_file(path, file_path, options = {})
      request = Net::HTTP::Post.new(request_uri(path))
      options[:partial_scan] ||= CopyleaksApi::Config.allow_partial_scan
      boundary = "copyleaks_sdk_#{SecureRandom.hex(4)}"
      request.body = file_body(file_path, boundary)
      make_request(request, options.merge(boundary: boundary))
    end

    private

    # extracts mime type of given file
    def extract_mime_type(path)
      mime = MimeMagic.by_magic(File.open(path))
      mime ? mime.type : 'text/plain'
    end

    # prepares post body with file inside
    def file_body(path, boundary)
      [
        "\r\n--#{boundary}\r\n",
        "content-disposition: form-data; name=\"file\"",
        "; filename=\"#{File.basename(path)}\"\r\n",
        "Content-Type: #{extract_mime_type(path)}\r\n",
        "Content-Transfer-Encoding: binary\r\n",
        "\r\n",
        File.open(path, 'rb') { |io| io.read },
        "\r\n--#{boundary}--\r\n"
      ].join('')
    end

    # gather all API path
    def request_uri(path)
      "/#{API_VERSION}/#{path}"
    end

    # gather headers, makes request and do validation
    def make_request(request, options)
      gather_headers(request, options)
      response = @http.request(request)
      Validators::ResponseValidator.validate!(response)
      JSON.parse(response.body)
    end

    # gather all headers
    def gather_headers(request, options)
      [
        http_callbacks_header(options),
        email_callback_header(options),
        authentication_header(options),
        sandbox_header,
        content_type_header(options),
        partial_scan_header(options),
        'User-Agent' => "RUBYSDK/#{CopyleaksApi::VERSION}"
      ].reduce({}, :merge).each do |header, value|
        request[header] = value
      end
    end

    # prepares header for sandbox mode
    def sandbox_header
      return {} unless Config.sandbox_mode
      { 'copyleaks-sandbox-mode' => '' }
    end

    # prepares header for content type
    def content_type_header(options)
      { 'Content-Type' => options[:boundary] ? "multipart/form-data; boundary=\"#{options[:boundary]}\"" :
                                               'application/json' }
    end

    # prepares header for partial scan
    def partial_scan_header(options)
      return {} unless !options[:allow_partial_scan].nil? && options[:allow_partial_scan] || Config.allow_partial_scan
      { 'copyleaks-allow-partial-scan' => '' }
    end

    # prepares authentication header
    def authentication_header(options)
      return {} unless options[:token]
      { 'Authorization' => "Bearer #{options[:token]}" }
    end

    # prepare header for http callback
    def http_callbacks_header(options)
      return {} if options[:no_http_callback] || options[:no_callbacks]
      value = options[:http_callback] || CopyleaksApi::Config.http_callback
      return {} unless value
      Validators::UrlValidator.validate!(value)
      { 'copyleaks-http-callback' => value }
    end

    # prepares header for email callback
    def email_callback_header(options)
      return {} if options[:no_email_callback] || options[:no_callbacks]
      value = options[:email_callback] || CopyleaksApi::Config.email_callback
      return {} unless value
      Validators::EmailValidator.validate!(value)
      { 'copyleaks-email-callback' => value }
    end

    # prepares headers with custom fields
    def custom_field_headers(options)
      return {} if options[:no_custom_fields]
      value = CopyleaksApi::Config.custom_fields.merge(options[:custom_fields] || {})
      Validators::CustomFieldsValidator.validate!(value)
      prepare_custom_fields(value)
    end

    # prepares custom fields before transformation into headers
    def prepare_custom_fields(fields)
      fields.each_with_object({}) { |e, o| o["copyleaks-client-custom-#{e[0]}"] = e[1] }
    end
  end
end

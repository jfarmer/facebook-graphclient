class FacebookError < StandardError
  attr_accessor :data
end

require 'digest/md5'
require 'yajl'
require 'patron'
require 'rack'

module Facebook
  GRAPH_URL = 'http://graph.facebook.com'

  class GraphClient

    attr_reader :secret, :app_id, :api_key
    attr_accessor :access_token

    def initialize facebook_settings = {}
      @app_id       = facebook_settings[:app_id]
      @api_key      = facebook_settings[:api_key]
      @secret       = facebook_settings[:secret]

      @cookie = get_user_cookie facebook_settings[:cookies]

      @access_token = facebook_settings[:access_token] || @cookie['access_token']

      @session = Patron::Session.new
    end

    def get_user_cookie cookies
      if cookies and cookie = cookies["fbs_#{@app_id}"]
        Rack::Utils.parse_nested_query(cookie)
      else
        {}
      end
    end

    %w[get post delete].each do |action|
      class_eval %[
      def #{action} method, params = {}
        self.api '#{action}', method, params
      end
      ]
    end

    def api action, method, query_params = nil
      query_params[:access_token] ||= @access_token

      query_string = '?' + query_params.map { |k,v| "#{k}=#{v}" }.join("&") unless query_params.empty?

      tries = 0
      begin
        raw_response = @session.send(action, GRAPH_URL + method + query_string)
      rescue Patron::HostResolutionError, Patron::ConnectionFailed
        retry if tries < 5
        tries += 1
      end

      # TODO: Handle photo requests, which return photo data and not JSON

      if raw_response.headers['Content-Type'] =~ /text\/javascript/
        # We have JSON
        response = Yajl::Parser.parse(raw_response.body)

        if e = response['error']
          error = FacebookError.new(e['message'])
          error.data = e
          raise error
        else
          response
        end
      end
    end

    def fql query
      query_params = {
        :access_token => @access_token,
        :format => 'json',
        :query => Rack::Utils.escape(query)
      }

      query_string = '?' + query_params.map { |k,v| "#{k}=#{v}" }.join("&") unless query_params.empty?

      tries = 0
      begin
        raw_response = @session.get("https://api.facebook.com/method/fql.query" + query_string)
      rescue Patron::HostResolutionError, Patron::ConnectionFailed
        retry if tries < 5
        tries += 1
      end

      response = Yajl::Parser.parse(raw_response.body)

      if e = response.first['error']
        error = FacebookError.new(e['message'])
        error.data = e
        raise error
      else
        response
      end
    end

    def valid?
      return false if @cookie.nil?

      unless @is_valid
        vars = @cookie.dup

        good_sig = vars.delete 'sig'
        sig = Digest::MD5.hexdigest(vars.sort.map { |k,v| "#{k}=#{v}" }.compact.join + @secret)

        if @is_valid = (sig == good_sig)
          @params = vars
        else
          @params = {}
        end
      end

      @is_valid
    end

    def [] k
      params[k]
    end

    def params
      valid? ? @params : {}
    end
  end
end

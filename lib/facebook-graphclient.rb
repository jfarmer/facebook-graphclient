class FacebookError < StandardError
  attr_accessor :data
end

require 'digest/md5'
require 'yajl'
require 'patron'
require 'rack'

module Facebook
  GRAPH_URL = 'https://graph.facebook.com'
  API_URL   = 'https://api.facebook.com/method/'

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

    def api action, method, query_params = {}
      query_params[:access_token] ||= @access_token
      query_string = '?' + query_params.map { |k,v| "#{k}=#{v}" }.join("&") unless query_params.empty?
      query_string ||= ''

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
        json = ["false", '', nil].include?(raw_response.body) ? '{}' : raw_response.body
        response = Yajl::Parser.parse(json)

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

      json = ["false", '', nil].include?(raw_response.body) ? '{}' : raw_response.body
      response = Yajl::Parser.parse(json)

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

    def rest(method, opts = {})
      if method == 'photos.upload'
        image = opts.delete :image
      end

      opts = { :api_key => self.api_key,
               :call_id => Time.now.to_f,
               :format => 'JSON',
               :v => '1.0',
               :access_token => @access_token,
               :session_key => %w[ photos.upload ].include?(method) ? nil : params[:session_key],
               :method => method }.merge(opts)

      args = opts.map{ |k,v|
                       next nil unless v

                       "#{k}=" + case v
                                 when Hash
                                   Yajl::Encoder.encode(v)
                                 when Array
                                   if k == :tags
                                     Yajl::Encoder.encode(v)
                                   else
                                     v.join(',')
                                   end
                                 else
                                   v.to_s
                                 end
                     }.compact.sort

      sig = Digest::MD5.hexdigest(args.join+self.secret)

      if method == 'photos.upload'
        data = MimeBoundary
        data += opts.merge(:sig => sig).inject('') do |buf, (key, val)|
          if val
            buf << (MimePart % [key, val])
          else
            buf
          end
        end
        data += MimeImage % ['upload.jpg', 'jpg', image.respond_to?(:read) ? image.read : image]
      else
        data = Array["sig=#{sig}", *args.map{|a| a.gsub('&','%26') }].join('&')
      end

      raw_response = @session.post(API_URL + method, data)

      json = ["false", '', nil].include?(raw_response.body) ? '{}' : raw_response.body
      response = Yajl::Parser.parse(json)

      if response.is_a?(Hash) and response.has_key?('error_code')
        error = FacebookError.new(response['error_msg'])
        error.data = response
        raise error
      else
        response
      end
    end
  end
end

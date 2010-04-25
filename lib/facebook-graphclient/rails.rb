begin
  require 'action_controller'
rescue LoadError
  retry if require 'rubygems'
  raise
end

require 'facebook-graphclient'

module Facebook
  module RailsFacebookSettings
    def self.extended(klass)
      klass.cattr_accessor :facebook_settings
      klass.facebook_settings = {}
    end
    def facebook(&blk)
      instance_eval(&blk)
      include Facebook::Rails
    end
    %w[ secret app_id access_token ].each do |param|
      class_eval %[
        def #{param} val, &blk
          facebook_settings[:#{param}] = val
        end
      ]
    end
  end

  module Rails
    def self.included(controller)
      if controller.respond_to?(:helper_method)
        controller.helper_method :fb, :facebook
      end
    end
    def facebook
      unless request.env['facebook.helper']
        fb = Facebook::GraphClient.new(self.class.facebook_settings.merge(:cookies => request.cookies))
        env['facebook.helper'] = fb
      end

      env['facebook.helper']
    end
    alias fb facebook
  end
end

ActionController::Base.extend Facebook::RailsFacebookSettings

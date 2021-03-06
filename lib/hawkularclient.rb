

require "json"
require "rest-client"

module Hawkular
  # Metrics module provides access to Hawkular Metrics REST API
  # @see http://www.hawkular.org/docs/rest/rest-metrics.html Hawkular Metrics REST API Documentation
  # @example Create Hawkular-Metrics client and start pushing some metric data
  #  # create client instance
  #  client = Hawkular::Metrics::Client::new("http://server","username","password",{"tenant" => "your tenant ID"})
  #  # push gauge metric data for metric called "myGauge" (no need to create metric definition unless you wish to specify data retention)
  #  client.gauges.push_data("myGauge", {:value => 3.1415925})
  module Metrics
  end
end

require "metrics/types"
require "metrics/tenant_api"
require "metrics/metric_api"


module Hawkular::Metrics

  class HawkularException < StandardError
    def initialize(message)
      @message = message
      super
    end

    def message
      @message
    end
  end

  class Client

    # @!visibility private
    attr_reader :credentials, :entrypoint, :options
    # @return [Tenants] access tenants API
    attr_reader :tenants
    # @return [Counters] access counters API
    attr_reader :counters
    # @return [Gauges] access gauges API
    attr_reader :gauges
    # @return [Availability] access counters API
    attr_reader :avail

    # Construct a new Hawkular Metrics client class.
    # optional parameters
    # @param entrypoint [String]
    # @param username [String]
    # @param password [String]
    # @param options [Hash{String=>String}] client options
    # @example initialize with Hawkular-tenant option
    #   Hawkular::Metrics::Client::new("http://server","username","password",{"tenant" => "your tenant ID"})
    #
    def initialize(entrypoint='http://localhost:8080/hawkular/metrics',username=nil, password=nil, options={})
      @entrypoint = entrypoint
      @credentials = { :username => username, :password => password }
      @options = {
        :tenant => nil,
      }.merge(options)

      @tenants = Client::Tenants::new self
      @counters = Client::Counters::new self
      @gauges = Client::Gauges::new self
      @avail = Client::Availability::new self
    end


    def http_get(suburl, headers={})
      begin
        res = rest_client(suburl).get(http_headers(headers))
        puts "#{res}\n" if ENV['HAWKULARCLIENT_LOG_RESPONSE']
        res.empty? ? {} : JSON.parse(res)
      rescue
        handle_fault $!
      end
    end


    def http_post(suburl, hash, headers={})
      begin
        body = JSON.generate(hash)
        res = rest_client(suburl).post(body, http_headers(headers))
        puts "#{res}\n" if ENV['HAWKULARCLIENT_LOG_RESPONSE']
        res.empty? ? {} : JSON.parse(res)
      rescue
        handle_fault $!
      end
    end

    def http_put(suburl, hash, headers={})
      begin
        body = JSON.generate(hash)
        res = rest_client(suburl).put(body, http_headers(headers))
        puts "#{res}\n" if ENV['HAWKULARCLIENT_LOG_RESPONSE']
        res.empty? ? {} : JSON.parse(res)
      rescue
        handle_fault $!
      end
    end

    def http_delete(suburl, headers={})
      begin
        res = rest_client(suburl).delete(http_headers(headers))
        puts "#{res}\n" if ENV['HAWKULARCLIENT_LOG_RESPONSE']
        res.empty? ? {} : JSON.parse(res)
      rescue
        handle_fault $!
      end
    end



    # @!visibility private
    def rest_client(suburl)
      options[:timeout] = ENV['HAWKULARCLIENT_REST_TIMEOUT'] if ENV['HAWKULARCLIENT_REST_TIMEOUT']
      # strip @endpoint in case suburl is absolute
      if suburl.match(/^http/)
        suburl = suburl[@entrypoint.length,suburl.length]
      end
      RestClient::Resource.new(@entrypoint, options)[suburl]
    end

    # @!visibility private
    def base_url
      url = URI.parse(@entrypoint)
      "#{url.scheme}://#{url.host}:#{url.port}"
    end

    # @!visibility private
    def self.parse_response(response)
      JSON.parse(response)
    end

    # @!visibility private
    def http_headers(headers ={})
      {}.merge(auth_header)
        .merge(tenant_header)
        .merge({
          :content_type => 'application/json',
          :accept => 'application/json',
        })
        .merge(headers)
    end

    # timestamp of current time
    # @return [Integer] timestamp
    def now
      Integer(Time::now.to_f * 1000)
    end

    private


      def tenant_header
        @options[:tenant].nil? ? {} : { :'Hawkular-Tenant' => @options[:tenant], "tenantId" => @options[:tenant] }
      end


      def auth_header
        if @credentials[:username].nil? and @credentials[:password].nil?
          return {}
        end
        # This is the method for strict_encode64:
        encoded_credentials = ["#{@credentials[:username]}:#{@credentials[:password]}"].pack("m0").gsub(/\n/,'')
        {:authorization => "Basic " + encoded_credentials }
      end

      def handle_fault(f)
        if defined? f.http_body and !f.http_body.nil?
          begin
            fault = "#{f.errorMsg}\n%s\n" % JSON.parse(f.http_body)["errorMsg"]
          rescue
            fault = f.http_body
            raise HawkularException::new(fault)
          end
        else
          raise f
        end

      end
  end

end

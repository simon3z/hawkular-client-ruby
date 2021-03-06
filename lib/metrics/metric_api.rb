module Hawkular::Metrics
  class Client

      # @!visibility private
      def default_timestamp(array)
        n = now
        array.each { |p|
          p[:timestamp] ||= n
        }
        array
      end


    # Push data for multiple metrics of all supported types
    # @param gauges [Array]
    # @param counters [Array]
    # @param availabilities [Array]
    # @example push datapoints of 2 counter metrics
    #    client = Hawkular::Metrics::client::new
    #    client.push_data(counters: [{:id => "counter1", :data => [{:value => 1}, {:value => 2}]},{:id => "counter2", :data => [{:value => 1}, {:value => 3}]}])
    # @example push gauge and availability datapoints
    #    client.push_data(gauges: [{:id => "gauge1", :data => [{:value => 1}, {:value => 2}]}], availabilities: [{:id => "avail1", :data => [{:value => "up"}]}])
    def push_data(gauges: [], counters: [], availabilities: [])
      gauges.each { |g|
        default_timestamp g[:data]
      }
      counters.each { |g|
        default_timestamp g[:data]
      }
      availabilities.each { |g|
        default_timestamp g[:data]
      }
      data = {:gauges => gauges, :counters => counters, :availabilities => availabilities}
      http_post("/metrics/data", data)
    end

    # Base class for accessing metric definition and data of all types (counters, gauges, availabilities)
    class Metrics

      # @param client [Client]
      # @param metricType [String] metric type (one of "counter", "gauge", "availability")
      # @param resource [String] REST resource name for accessing metrics of given type (one of "counters", "gauges", "availability")
      def initialize(client, metricType, resource)
        @client = client
        @type = metricType
        @resource = resource
      end

      # Create new  metric definition
      # @param definition [MetricDefinition or Hash] gauge/counter/availability options.
      # @example Create gauge metric definition using Hash
      #   client = Hawkular::Metrics::client::new
      #   client.gauges.create({:id => "id", :dataRetention => 90, :tags => {:tag1 => "value1"}, :tenantId => "your tenant id"})
      def create(definition)
        if definition.kind_of?(Hawkular::Metrics::MetricDefinition)
          definition = definition.hash
        end
        @client.http_post('/'+@resource, definition)
      end

      # Query metric definitions by tags
      # @param tags [Hash]
      # @return [Array[MetricDefinition]]
      def query(tags)
          tags = tags.map do |k,v|
            "#{k}:#{v}"
          end
          @client.http_get("/metrics/?type=#{@type}&tags=#{tags.join(',')}").map do |g|
            Hawkular::Metrics::MetricDefinition::new(g)
          end
      end

      # Get metric definition by id
      # @param id [String]
      # @return [MetricDefinition]
      def get(id)
        Hawkular::Metrics::MetricDefinition::new(@client.http_get("/#{@resource}/#{id}"))
      end

      # update tags for given metric definition
      # @param metricDefinition [MetricDefinition]
      def update_tags(metricDefinition)
        @client.http_put("/#{@resource}/#{metricDefinition.id}/tags",metricDefinition.hash[:tags])
      end

      # Push metric data
      # @param id [String] metric definition ID
      # @param data [Array[Hash]] Single datapoint or array of datapoints
      # @example Push counter data with timestamp
      #   client = Hawkular::Metics::Client::new
      #   now = Integer(Time::now.to_f * 1000)
      #   client.counters.push_data("counter id", [{:value => 1, :timestamp => now - 1000}, {:value => 2, :timestamp => now}])
      # @example Push single availability without timestamp
      #   client.avail.push_data("avail_id", {:value => "up"})
      # @example Push gague data with tags
      #   client.gagues.push_data("gauge_id", [{:value => 0.1, :tags => {:tagName => "myMin"}},{:value => 99.9, :tags => {:tagName => "myMax"}}])
      def push_data(id, data)
        if !data.kind_of?(Array)
          data = [data]
        end

        @client.default_timestamp data
        @client.http_post("/#{@resource}/#{id}/data", data)
      end

      # Retrieve metric datapoints
      # @param id [String] metric definition id
      # @param starts [Integer] optional timestamp (default now - 8h)
      # @param ends [Integer] optional timestamp (default now)
      # @return [Array[Hash]] datapoints
      # @see #push_data #push_data for datapoint detail
      def get_data(id, starts: nil, ends: nil)
        params = {:start => starts, :end => ends}
        params.delete_if { |k, v| v.nil? }
        resp = @client.http_get("/#{@resource}/#{id}/data/?"+URI.encode_www_form(params))
        return [] if !resp.kind_of?(Array) # API returns no content (empty Hash) instead of empty array
        resp
      end
    end

    # Class that interracts with "gauge" metric types
    class Gauges < Metrics

      # @param client [Client]
      def initialize(client)
        super(client, 'gauge', 'gauges')
      end

      # Retrieve time ranges when given gauge matches given operation and threshold
      # @param id [String] gauge ID
      # @param starts [Integer] timestamp (default now - 8h)
      # @param ends [Integer] timestamp (default now)
      # @param threshold [Numeric]
      # @param operation [String] A comparison operation to perform between values and the threshold. Supported operations include "ge", "gte", "lt", "lte", and "eq"
      # @example Get time periods when metric "gauge1" was under 10 in past 4 hours
      #   before4h = client.now - (4 * 60 * 60 * 1000)
      #   client.gauges.get_periods("gauge1", starts: before4h, threshold: 10, operation: "lte")
      def get_periods(id, starts: nil, ends: nil, threshold:, operation:)
          params = {:start => starts, :end => ends, :threshold => threshold, :op => operation}
          params.delete_if { |k, v| v.nil? }
          @client.http_get("/#{@resource}/#{id}/periods?"+URI.encode_www_form(params))
      end

    end

    # Class that interracts with "counter" metric types
    class Counters < Metrics

      # @param client [Client]
      def initialize(client)
        super(client, 'counter', 'counters')
      end

      # get rate for given metric
      # @param id [String] metric ID
      def get_rate(id:)
        @client.http_get("/#{@resource}/#{id}/rate")
      end
    end

    # Class that interracts with "availability" metric types
    class Availability < Metrics

      # @param client [Client]
      def initialize(client)
        super(client, 'availability', 'availability')
      end

    end


    private


  end
end

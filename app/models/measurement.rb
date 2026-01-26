# frozen_string_literal: true

module Checker
  class Measurement < Sequel::Model(:measurements)
    many_to_one :host

    plugin :timestamps, create: :created_at, update: false

    def self.for_host(host_id, since: nil, until_time: nil)
      ds = where(host_id: host_id)
      ds = ds.where { tested_at >= since } if since
      ds = ds.where { tested_at <= until_time } if until_time
      ds.order(:tested_at)
    end

    def self.time_range_to_interval(range)
      case range
      when '1h' then 1 * 60 * 60
      when '6h' then 6 * 60 * 60
      when '24h' then 24 * 60 * 60
      when '7d' then 7 * 24 * 60 * 60
      when '30d' then 30 * 24 * 60 * 60
      else 24 * 60 * 60
      end
    end

    def self.parse_time_range(range: nil, start_time: nil, end_time: nil)
      if start_time && end_time
        [Time.parse(start_time), Time.parse(end_time)]
      else
        interval = time_range_to_interval(range || '24h')
        [Time.now - interval, Time.now]
      end
    end

    def self.latency_series(range: '24h', start_time: nil, end_time: nil)
      since, until_time = parse_time_range(range: range, start_time: start_time, end_time: end_time)

      Host.enabled.map do |host|
        measurements = for_host(host.id, since: since, until_time: until_time).all
        {
          name: host.name,
          data: measurements.map do |m|
            [m.tested_at.to_i * 1000, m.latency_ms&.round(2)]
          end
        }
      end
    end

    def self.latency_series_by_type(range: '24h', start_time: nil, end_time: nil)
      since, until_time = parse_time_range(range: range, start_time: start_time, end_time: end_time)

      # Group hosts by test type
      hosts_by_type = Host.enabled.all.group_by(&:test_type)

      result = {}
      hosts_by_type.each do |test_type, hosts|
        result[test_type] = hosts.map do |host|
          measurements = for_host(host.id, since: since, until_time: until_time).all
          {
            name: host.name,
            data: measurements.map do |m|
              [m.tested_at.to_i * 1000, m.latency_ms&.round(2)]
            end
          }
        end
      end

      result
    end

    def self.test_types_with_hosts
      Host.enabled.all.map(&:test_type).uniq.sort
    end

    def self.jitter_series(range: '24h', start_time: nil, end_time: nil)
      since, until_time = parse_time_range(range: range, start_time: start_time, end_time: end_time)

      Host.enabled.map do |host|
        measurements = for_host(host.id, since: since, until_time: until_time).all
        {
          name: host.name,
          data: measurements.map do |m|
            [m.tested_at.to_i * 1000, m.jitter_ms&.round(2)]
          end
        }
      end
    end

    def self.reachability_series(range: '24h', start_time: nil, end_time: nil)
      since, until_time = parse_time_range(range: range, start_time: start_time, end_time: end_time)

      Host.enabled.map do |host|
        measurements = for_host(host.id, since: since, until_time: until_time).all
        # Group by hour and calculate percentage
        grouped = measurements.group_by { |m| m.tested_at.strftime('%Y-%m-%d %H:00') }
        {
          name: host.name,
          data: grouped.map do |time_str, group|
            success_rate = (group.count(&:reachable).to_f / group.count * 100).round(1)
            [Time.parse(time_str).to_i * 1000, success_rate]
          end
        }
      end
    end
  end
end

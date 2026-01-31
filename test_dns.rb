#!/usr/bin/env ruby
# Standalone DNS test script

require 'resolv'

# Default values or command line args
dns_server = ARGV[0] || '9.9.9.9'
query_hostname = ARGV[1] || 'www.ibm.com'
dns_timeout = (ARGV[2] || 5).to_i

puts "=" * 60
puts "DNS Test Script"
puts "=" * 60
puts "DNS Server: #{dns_server}"
puts "Query Hostname: #{query_hostname}"
puts "Timeout: #{dns_timeout} seconds"
puts "=" * 60

start_time = Time.now

# Test 1: Simple default resolver (uses system DNS)
puts "\n[Test 1] Using default system resolver..."
begin
  resolver = Resolv::DNS.new
  addresses = resolver.getaddresses(query_hostname)
  puts "✓ Success! Resolved to: #{addresses.map(&:to_s).join(', ')}"
rescue => e
  puts "✗ Failed: #{e.class} - #{e.message}"
end

# Test 2: Custom nameserver with nameserver parameter (array of IPs)
puts "\n[Test 2] Using nameserver parameter (array)..."
begin
  resolver = Resolv::DNS.new(nameserver: [dns_server])
  addresses = resolver.getaddresses(query_hostname)
  puts "✓ Success! Resolved to: #{addresses.map(&:to_s).join(', ')}"
rescue => e
  puts "✗ Failed: #{e.class} - #{e.message}"
  puts "  Backtrace: #{e.backtrace.first(3).join("\n  ")}"
end

# Test 3: Custom nameserver with nameserver_port parameter
puts "\n[Test 3] Using nameserver_port parameter..."
begin
  resolver = Resolv::DNS.new(nameserver_port: [[dns_server, 53]])
  addresses = resolver.getaddresses(query_hostname)
  puts "✓ Success! Resolved to: #{addresses.map(&:to_s).join(', ')}"
rescue => e
  puts "✗ Failed: #{e.class} - #{e.message}"
  puts "  Backtrace: #{e.backtrace.first(3).join("\n  ")}"
end

# Test 4: With Thread timeout (like our actual code)
puts "\n[Test 4] Using Thread-based timeout with nameserver parameter..."
begin
  query_thread = Thread.new do
    begin
      resolver = Resolv::DNS.new(nameserver: [dns_server])

      addresses = resolver.getaddresses(query_hostname)

      if addresses.any?
        { success: true, addresses: addresses.map(&:to_s) }
      else
        { success: false, error: "No addresses returned" }
      end
    rescue => e
      { success: false, error: "#{e.class}: #{e.message}" }
    end
  end

  result = query_thread.join(dns_timeout)

  if result.nil?
    query_thread.kill
    puts "✗ Timeout occurred after #{dns_timeout} seconds"
  else
    thread_result = query_thread.value
    if thread_result[:success]
      puts "✓ Success! Resolved to: #{thread_result[:addresses].join(', ')}"
    else
      puts "✗ Failed: #{thread_result[:error]}"
    end
  end
rescue => e
  puts "✗ Exception: #{e.class} - #{e.message}"
  puts "  Backtrace: #{e.backtrace.first(3).join("\n  ")}"
end

elapsed = Time.now - start_time
puts "\n" + "=" * 60
puts "Total time: #{elapsed.round(2)} seconds"
puts "=" * 60

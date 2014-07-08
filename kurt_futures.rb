#################################
# Based on a discussion with Jeff.
#

require 'thread'

class Future
  def self.future &blk
    self.new(&blk)
  end

  def initialize &blk
    @queue = Queue.new
    @value_mutex = Mutex.new
    with(&blk) if blk
  end

  def with &blk
    worker.enq([blk, lambda { | value | @queue.enq value }])
  end

  def value
    @value_mutex.synchronize do
      unless @value_
        @value_ = true
        $stderr.puts "  value begin"
        value = @queue.deq
        type, value = value
        case type
        when :value
          @value = value
        when :exc
          raise value
        else
          raise "unexpected #{type.inspect}"
        end
        $stderr.puts "  value end"
      end
      @value
    end
  end

  def call value
    @queue.enq value
  end

  def worker
    @@worker ||= Worker.new.start!
  end
  @@worker = nil

  class Worker
    attr_accessor :queue, :running, :stop, :stopping, :stopped

    def initialize
      @queue = Queue.new
    end

    def enq job
      raise "stop" if stop
      queue.enq job
      self
    end

    def stop!
      if @thread && ! stop
        stop = true
        queue.enq :stop
      end
      self
    end

    def join
      if @thread
        stop!
        @thread.join
        @thread = nil
      end
      self
    end

    def start!
      @thread ||= Thread.new do | thread |
        begin
          self.running = true
          while ! stop and job = queue.deq
            case job
            when :stop
              self.stop = self.stopping = true
            else
              job, result = job
              begin
                $stderr.puts "  job begin #{job.inspect}"
                val = job.call
                $stderr.puts "  job end"
                result.call([:value, val])
              rescue => exc
                $stderr.puts "  job error #{exc.inspect}"
                result.call([:exc, exc])
              end
            end
          end
        ensure
          self.running = self.stopping = false
          self.stopped = true
        end
      end
      self
    end
  end
end

#########################

a = Future.future do
  10.times do | i |
    $stderr.puts "future #{i}"
    sleep 0.2
  end
  1234
end

$stderr.puts "before a.value"
5.times do | i |
  $stderr.puts "main #{i}"
  sleep 0.2
end

puts a.value

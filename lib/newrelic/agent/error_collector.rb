require 'newrelic/agent/synchronize'
require 'newrelic/noticed_error'
require 'logger'

module NewRelic::Agent
  class ErrorCollector
    include Synchronize
    
    MAX_ERROR_QUEUE_LENGTH = 20 unless defined? MAX_ERROR_QUEUE_LENGTH
    
    def initialize(agent = nil)
      @agent = agent
      @errors = []
      @ignore = {}
      @ignore_filter = nil
    end
    
    
    def ignore_error_filter(&block)
      @ignore_filter = block
    end
    
    
    # errors is an array of String exceptions
    #
    def ignore(errors)
      errors.each { |error| @ignore[error] = true; log.debug("Ignoring error: '#{error}'") }
    end
   
    
    def notice_error(path, params, exception)
      
      return if @ignore[exception.class.name]
      
      if @ignore_filter
        exception = @ignore_filter.call(exception)
        
        return if exception.nil?
      end
      
      @@error_stat ||= NewRelic::Agent.get_stats("Errors/all")
      
      @@error_stat.increment_count
      
      data = {}
      
      data[:request_params] = params
      data[:stack_trace] = exception.backtrace
      
      noticed_error = NoticedError.new(path, data, exception)
      
      synchronize do
        if @errors.length >= MAX_ERROR_QUEUE_LENGTH
          log.info("Not reporting error (queue exceeded maximum length): #{exception.message}")
        else
          @errors << noticed_error
        end
      end
    end
    
    def harvest_errors(unsent_errors)
      synchronize do
        errors = (unsent_errors || []) + @errors
        @errors = []
        return errors
      end
    end
    
  private
    def log 
      return @agent.log if @agent && @agent.log
      
      @backup_log ||= Logger.new(STDERR)
    end
  end
end
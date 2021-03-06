require 'enumerator'
require 'merb-core/controller/mime'
module Merb
  # The ResponderMixin adds methods that help you manage what
  # formats your controllers have available, determine what format(s)
  # the client requested and is capable of handling, and perform
  # content negotiation to pick the proper content format to
  # deliver.
  # 
  # If you hear someone say "Use provides" they're talking about the
  # Responder.  If you hear someone ask "What happened to respond_to?"
  # it was replaced by provides and the other Responder methods.
  # 
  # == A simple example
  # 
  # The best way to understand how all of these pieces fit together is
  # with an example.  Here's a simple web-service ready resource that
  # provides a list of all the widgets we know about.  The widget list is 
  # available in 3 formats: :html (the default), plus :xml and :text.
  # 
  #     class Widgets < Application
  #       provides :html   # This is the default, but you can
  #                        # be explicit if you like.
  #       provides :xml, :text
  #       
  #       def index
  #         @widgets = Widget.fetch
  #         render @widgets
  #       end
  #     end
  # 
  # Let's look at some example requests for this list of widgets.  We'll
  # assume they're all GET requests, but that's only to make the examples
  # easier; this works for the full set of RESTful methods.
  # 
  # 1. The simplest case, /widgets.html
  #    Since the request includes a specific format (.html) we know
  #    what format to return.  Since :html is in our list of provided
  #    formats, that's what we'll return.  +render+ will look
  #    for an index.html.erb (or another template format
  #    like index.html.mab; see the documentation on Template engines)
  # 
  # 2. Almost as simple, /widgets.xml
  #    This is very similar.  They want :xml, we have :xml, so
  #    that's what they get.  If +render+ doesn't find an 
  #    index.xml.builder or similar template, it will call +to_xml+
  #    on @widgets.  This may or may not do something useful, but you can 
  #    see how it works.
  #
  # 3. A browser request for /widgets
  #    This time the URL doesn't say what format is being requested, so
  #    we'll look to the HTTP Accept: header.  If it's '*/*' (anything),
  #    we'll use the first format on our list, :html by default.
  #    
  #    If it parses to a list of accepted formats, we'll look through 
  #    them, in order, until we find one we have available.  If we find
  #    one, we'll use that.  Otherwise, we can't fulfill the request: 
  #    they asked for a format we don't have.  So we raise
  #    406: Not Acceptable.
  # 
  # == A more complex example
  # 
  # Sometimes you don't have the same code to handle each available 
  # format. Sometimes you need to load different data to serve
  # /widgets.xml versus /widgets.txt.  In that case, you can use
  # +content_type+ to determine what format will be delivered.
  # 
  #     class Widgets < Application
  #       def action1
  #         if content_type == :text
  #           Widget.load_text_formatted(params[:id])
  #         else
  #           render
  #         end
  #       end
  #       
  #       def action2
  #         case content_type
  #         when :html
  #           handle_html()
  #         when :xml
  #           handle_xml()
  #         when :text
  #           handle_text()
  #         else
  #           render
  #         end
  #       end
  #     end
  # 
  # You can do any standard Ruby flow control using +content_type+.  If
  # you don't call it yourself, it will be called (triggering content
  # negotiation) by +render+.
  #
  # Once +content_type+ has been called, the output format is frozen,
  # and none of the provides methods can be used.
  module ResponderMixin
    
    TYPES = {}

    class ContentTypeAlreadySet < StandardError; end
    
    # ==== Parameters
    # base<Module>:: The module that ResponderMixin was mixed into
    def self.included(base) # :nodoc:
      base.extend(ClassMethods)
      base.class_eval do
        class_inheritable_accessor :class_provided_formats
        self.class_provided_formats = []
      end
      base.reset_provides
    end

    module ClassMethods
      
      # Adds symbols representing formats to the controller's default list of
      # provided_formats. These will apply to every action in the controller,
      # unless modified in the action. If the last argument is a Hash or an
      # Array, these are regarded as arguments to pass to the to_<mime_type>
      # method as needed.
      #
      # ==== Parameters
      # *formats<Symbol>::
      #   A list of mime-types that the controller should provide.
      #
      # ==== Returns
      # Array[Symbol]:: List of formats passed in.
      #
      # ==== Examples
      #   provides :html, :xml
      #---
      # @public
      def provides(*formats)
        formats.each do |fmt|
          self.class_provided_formats << fmt unless class_provided_formats.include?(fmt)
        end
      end
      
      # This class should only provide the formats listed here, despite any
      # other definitions previously or in superclasses.
      #
      # ==== Parameters
      # *formats<Symbol>:: Registered mime-types.
      # 
      # ==== Returns
      # Array[Symbol]:: List of formats passed in.      
      #
      #---
      # @public
      def only_provides(*formats)
        clear_provides
        provides(*formats)
      end

      # This class should not provide any of this list of formats, despite any.
      # other definitions previously or in superclasses.
      # 
      # ==== Parameters
      # *formats<Symbol>:: Registered mime-types.
      # 
      # ==== Returns
      # Array[Symbol]::
      #   List of formats that remain after removing the ones not to provide.
      #
      #---
      # @public
      def does_not_provide(*formats)
        self.class_provided_formats -= formats
      end

      # Clear the list of provides.
      #
      # ==== Returns
      # Array:: An empty Array.
      def clear_provides
        self.class_provided_formats.clear
      end
      
      # Reset the list of provides to include only :html.
      #
      # ==== Returns
      # Array[Symbol]:: [:html].
      def reset_provides
        only_provides(:html)
      end
    end

    # ==== Returns
    # Array[Symbol]::
    #   The current list of formats provided for this instance of the
    #   controller. It starts with what has been set in the controller (or
    #   :html by default) but can be modifed on a per-action basis.      
    def _provided_formats
      @_provided_formats ||= class_provided_formats.dup
    end
    
    # Sets the provided formats for this action.  Usually, you would use a
    # combination of provides, only_provides and does_not_provide to manage
    # this, but you can set it directly.
    # 
    # ==== Parameters
    # *formats<Symbol>:: A list of formats to be passed to provides.
    #
    # ==== Raises
    # Merb::ResponderMixin::ContentTypeAlreadySet::
    #   Content negotiation already occured, and the content_type is set.
    #
    # ==== Returns
    # Array[Symbol]:: List of formats passed in.
    def _set_provided_formats(*formats)
      if @_content_type
        raise ContentTypeAlreadySet, "Cannot modify provided_formats because content_type has already been set"
      end
      @_provided_formats = []
      provides(*formats)
    end
    alias :_provided_formats= :_set_provided_formats   
    
    # Adds formats to the list of provided formats for this particular request.
    # Usually used to add formats to a single action. See also the
    # controller-level provides that affects all actions in a controller.
    #
    # ==== Parameters
    # *formats<Symbol>::
    #   A list of formats to add to the per-action list of provided formats.
    #
    # ==== Raises
    # Merb::ResponderMixin::ContentTypeAlreadySet::
    #   Content negotiation already occured, and the content_type is set.
    #
    # ==== Returns
    # Array[Symbol]:: List of formats passed in.
    #
    #---
    # @public
    def provides(*formats)
      if @_content_type
        raise ContentTypeAlreadySet, "Cannot modify provided_formats because content_type has already been set"
      end
      formats.each do |fmt|
        _provided_formats << fmt unless _provided_formats.include?(fmt)
      end
    end

    # Sets list of provided formats for this particular request. Usually used
    # to limit formats to a single action. See also the controller-level
    # only_provides that affects all actions in a controller.      
    # 
    # ==== Parameters
    # *formats<Symbol>::
    #   A list of formats to use as the per-action list of provided formats.
    #
    # ==== Returns
    # Array[Symbol]:: List of formats passed in.
    #
    #---
    # @public
    def only_provides(*formats)
      self._provided_formats = *formats
    end
    
    # Removes formats from the list of provided formats for this particular 
    # request. Usually used to remove formats from a single action.  See
    # also the controller-level does_not_provide that affects all actions in a
    # controller.
    #
    # ==== Parameters
    # *formats<Symbol>:: Registered mime-type
    # 
    # ==== Returns
    # Array[Symbol]::
    #   List of formats that remain after removing the ones not to provide.
    #
    #---
    # @public
    def does_not_provide(*formats)
      formats.flatten!
      self._provided_formats -= formats
    end
    
    # Do the content negotiation:
    # 1. if params[:format] is there, and provided, use it
    # 2. Parse the Accept header
    # 3. If it's */*, use the first provided format
    # 4. Look for one that is provided, in order of request
    # 5. Raise 406 if none found
    def _perform_content_negotiation # :nodoc:
      raise Merb::ControllerExceptions::NotAcceptable if _provided_formats.empty?
      if (fmt = params[:format]) && !fmt.empty?
        accepts = [fmt.to_sym]
      else
        accepts = Responder.parse(request.accept).map {|t| t.to_sym}.compact
      end
      specifics = accepts & _provided_formats
      return specifics.first unless specifics.length == 0
      return _provided_formats.first if accepts.include? :all
      raise Merb::ControllerExceptions::NotAcceptable
    end

    # Returns the output format for this request, based on the 
    # provided formats, <tt>params[:format]</tt> and the client's HTTP
    # Accept header.
    #
    # The first time this is called, it triggers content negotiation
    # and caches the value.  Once you call +content_type+ you can
    # not set or change the list of provided formats.
    #
    # Called automatically by +render+, so you should only call it if
    # you need the value, not to trigger content negotiation. 
    # 
    # ==== Parameters
    # fmt<String>:: 
    #   An optional format to use instead of performing content negotiation.
    #   This can be used to pass in the values of opts[:format] from the 
    #   render function to short-circuit content-negotiation when it's not
    #   necessary. This optional parameter should not be considered part
    #   of the public API.
    #
    # ==== Returns
    # Symbol:: The content-type that will be used for this controller.
    #
    #---
    # @public
    def content_type(fmt = nil)
      self.content_type = (fmt || _perform_content_negotiation) unless @_content_type
      @_content_type
    end
    
    # Sets the content type of the current response to a value based on 
    # a passed in key. The Content-Type header will be set to the first
    # registered header for the mime-type.
    #
    # ==== Parameters
    # type<Symbol>:: The content type.
    #
    # ==== Raises
    # ArgumentError:: type is not in the list of registered mime-types.
    #
    # ==== Returns
    # Symbol:: The content-type that was passed in.
    #
    #---
    # @semipublic
    def content_type=(type)
      unless Merb.available_mime_types.has_key?(type)
        raise Merb::ControllerExceptions::NotAcceptable.new("Unknown content_type for response: #{type}") 
      end        
      headers['Content-Type'] = Merb.available_mime_types[type][:request_headers].first
      @_content_type = type
    end
    
  end

  class Responder
  
    protected

    # Parses the raw accept header into an array of sorted AcceptType objects.
    #
    # ==== Parameters
    # accept_header<~to_s>:: The raw accept header.
    #
    # ==== Returns
    # Array[AcceptType]:: The accepted types.
    def self.parse(accept_header)
      list = accept_header.to_s.split(/,/).enum_for(:each_with_index).map do |entry,index|
        AcceptType.new(entry,index += 1)
      end.sort.uniq
      # firefox (and possibly other browsers) send broken default accept headers.
      # fix them up by sorting alternate xml forms (namely application/xhtml+xml)
      # ahead of pure xml types (application/xml,text/xml).
      if app_xml = list.detect{|e| e.super_range == 'application/xml'}
        list.select{|e| e.to_s =~ /\+xml/}.each { |acc_type|
          list[list.index(acc_type)],list[list.index(app_xml)] = 
            list[list.index(app_xml)],list[list.index(acc_type)] }
      end
      list
    end   
      
  end

  class AcceptType

    attr_reader :media_range, :quality, :index, :type, :sub_type

    # ==== Parameters
    # entry<String>:: The accept type pattern
    # index<Fixnum>::
    #   The index used for sorting accept types. A lower value indicates higher
    #   priority.
    def initialize(entry,index)
      @index = index
      @media_range, quality = entry.split(/;\s*q=/).map{|a| a.strip }
      @type, @sub_type = @media_range.split(/\//)
      quality ||= 0.0 if @media_range == '*/*'
      @quality = ((quality || 1.0).to_f * 100).to_i
    end

    # Compares two accept types for sorting purposes.
    #
    # ==== Parameters
    # entry<AcceptType>:: The accept type to compare.
    #
    # ==== Returns
    # Fixnum::
    #   -1, 0 or 1, depending on whether entry has a lower, equal or higher
    #   priority than the accept type being compared.
    def <=>(entry)
      c = entry.quality <=> quality
      c = index <=> entry.index if c == 0
      c
    end

    # ==== Parameters
    # entry<AcceptType>:: The accept type to compare.
    #
    # ==== Returns
    # Boolean::
    #   True if the accept types are equal, i.e. if the synonyms for this
    #   accept type includes the entry media range.
    def eql?(entry)
      synonyms.include?(entry.media_range)
    end

    # An alias for eql?.
    def ==(entry); eql?(entry); end

    # ==== Returns
    # Fixnum:: A hash based on the super range.
    def hash; super_range.hash; end

    # ==== Returns
    # Array[String]::
    #   All Accept header values, such as "text/html", that match this type.
    def synonyms
      @syns ||= Merb.available_mime_types.values.map do |e| 
        e[:request_headers] if e[:request_headers].include?(@media_range)
      end.compact.flatten
    end

    # ==== Returns
    # String::
    #   The primary media range for this accept type, i.e. either the first
    #   synonym or, if none exist, the media range.
    def super_range
      synonyms.first || @media_range
    end

    # ==== Returns
    # Symbol: The type as a symbol, e.g. :html.
    def to_sym
      Merb.available_mime_types.select{|k,v| 
        v[:request_headers] == synonyms || v[:request_headers][0] == synonyms[0]}.flatten.first
    end

    # ==== Returns
    # String:: The accept type as a string, i.e. the media range.
    def to_s
      @media_range
    end
  
  end

end

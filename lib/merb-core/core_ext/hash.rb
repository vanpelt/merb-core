require 'base64'

class Hash
  class << self
    # Converts valid XML into a Ruby Hash structure.
    #
    # ==== Paramters
    # xml<String>:: A string representation of valid XML.
    #
    # ==== Notes
    # * Mixed content is treated as text and any tags in it are left unparsed
    # * Any attributes other than type on a node containing a text node will be
    #   discarded
    #
    # ===== Typecasting
    # Typecasting is performed on elements that have a +type+ attribute:
    # integer:: 
    # boolean:: Anything other than "true" evaluates to false.
    # datetime::
    #   Returns a Time object. See Time documentation for valid Time strings.
    # date::
    #   Returns a Date object. See Date documentation for valid Date strings.
    # 
    # Keys are automatically converted to +snake_case+
    #
    # ==== Examples
    #
    # ===== Standard
    #   <user gender='m'>
    #     <age type='integer'>35</age>
    #     <name>Home Simpson</name>
    #     <dob type='date'>1988-01-01</dob>
    #     <joined-at type='datetime'>2000-04-28 23:01</joined-at>
    #     <is-cool type='boolean'>true</is-cool>
    #   </user>
    #
    # evaluates to 
    # 
    #   { "user" => { 
    #       "gender"    => "m",
    #       "age"       => 35,
    #       "name"      => "Home Simpson",
    #       "dob"       => DateObject( 1998-01-01 ),
    #       "joined_at" => TimeObject( 2000-04-28 23:01),
    #       "is_cool"   => true 
    #     }
    #   }
    #
    # ===== Mixed Content
    #   <story>
    #     A Quick <em>brown</em> Fox
    #   </story>
    #
    # evaluates to
    #
    #   { "story" => "A Quick <em>brown</em> Fox" }
    # 
    # ====== Attributes other than type on a node containing text
    #   <story is-good='false'>
    #     A Quick <em>brown</em> Fox
    #   </story>
    #
    # evaluates to
    #
    #   { "story" => "A Quick <em>brown</em> Fox" }
    #
    #   <bicep unit='inches' type='integer'>60</bicep>
    #
    # evaluates with a typecast to an integer. But unit attribute is ignored.
    #
    #    { "bicep" => 60 }
    def from_xml( xml )
      ToHashParser.from_xml(xml)
    end
  end
  
  # ==== Returns
  # Mash:: This hash as a Mash for string or symbol key access.
  def to_mash
    hash = Mash.new(self)
    hash.default = default
    hash
  end
  
  # ==== Returns
  # String:: This hash as a query string
  #
  # ==== Examples
  #   { :name => "Bob",
  #     :address => {
  #       :street => '111 Ruby Ave.',
  #       :city => 'Ruby Central',
  #       :phones => ['111-111-1111', '222-222-2222']
  #     }
  #   }.to_params
  #     #=> "name=Bob&address[city]=Ruby Central&address[phones]=111-111-1111222-222-2222&address[street]=111 Ruby Ave."
  def to_params
    params = ''
    stack = []
    
    each do |k, v|
      if v.is_a?(Hash)
        stack << [k,v]
      else
        params << "#{k}=#{v}&"
      end
    end
    
    stack.each do |parent, hash|
      hash.each do |k, v|
        if v.is_a?(Hash)
          stack << ["#{parent}[#{k}]", v]
        else
          params << "#{parent}[#{k}]=#{v}&"
        end
      end
    end
    
    params.chop! # trailing &
    params
  end
  
  # ==== Parameters
  # *allowed:: The hash keys to include.
  #
  # ==== Returns
  # Hash:: A new hash with only the selected keys.
  #
  # ==== Examples
  #   { :one => 1, :two => 2, :three => 3 }.only(:one)
  #     #=> { :one => 1 }
  def only(*allowed) 
    reject { |k,v| !allowed.include?(k) }
  end
  
  # ==== Parameters
  # *rejected:: The hash keys to exclude.
  #
  # ==== Returns
  # Hash:: A new hash without the selected keys.
  #
  # ==== Examples
  #   { :one => 1, :two => 2, :three => 3 }.except(:one)
  #     #=> { :two => 2, :three => 3 }
  def except(*rejected) 
    reject { |k,v| rejected.include?(k) }
  end
  
  # ==== Returns
  # String:: The hash as attributes for an XML tag.
  #
  # ==== Examples
  #   { :one => 1, "two"=>"TWO" }.to_xml_attributes
  #     #=> 'one="1" two="TWO"'
  def to_xml_attributes
    map do |k,v|
      %{#{k.to_s.camel_case.sub(/^(.{1,1})/) { |m| m.downcase }}="#{v}"} 
    end.join(' ')
  end
  
  alias_method :to_html_attributes, :to_xml_attributes
  
  # ==== Parameters
  # html_class<~to_s>::
  #   The HTML class to add to the :class key. The html_class will be
  #   concatenated to any existing classes.
  #
  # ==== Examples
  #   hash[:class] #=> nil
  #   hash.add_html_class!(:selected)
  #   hash[:class] #=> "selected"
  #   hash.add_html_class!("class1 class2")
  #   hash[:class] #=> "selected class1 class2"
  def add_html_class!(html_class)
    if self[:class]
      self[:class] = "#{self[:class]} #{html_class}"
    else
      self[:class] = html_class.to_s
    end
  end
  
  # Converts all keys into string values. This is used during reloading to
  # prevent problems when classes are no longer declared.
  #
  # === Examples
  #   hash = { One => 1, Two => 2 }.proctect_keys!
  #   hash # => { "One" => 1, "Two" => 2 }
  def protect_keys!
    keys.each {|key| self[key.to_s] = delete(key) }
  end
  
  # Attempts to convert all string keys into Class keys. We run this after
  # reloading to convert protected hashes back into usable hashes.
  #
  # === Examples
  #   # Provided that classes One and Two are declared in this scope:
  #   hash = { "One" => 1, "Two" => 2 }.unproctect_keys!
  #   hash # => { One => 1, Two => 2 }
  def unprotect_keys!
    keys.each do |key| 
      (self[Object.full_const_get(key)] = delete(key)) rescue nil
    end
  end
  
  # Destructively and non-recursively convert each key to an uppercase string,
  # deleting nil values along the way.
  #
  # ==== Returns
  # Hash:: The newly environmentized hash.
  #
  # ==== Examples
  #   { :name => "Bob", :contact => { :email => "bob@bob.com" } }.environmentize_keys!
  #     #=> { "NAME" => "Bob", "CONTACT" => { :email => "bob@bob.com" } }
  def environmentize_keys!
    keys.each do |key|
      val = delete(key)
      next if val.nil?
      self[key.to_s.upcase] = val
    end
    self
  end  
end

require 'rexml/parsers/streamparser'
require 'rexml/parsers/baseparser'
require 'rexml/light/node'

# This is a slighly modified version of the XMLUtilityNode from
# http://merb.devjavu.com/projects/merb/ticket/95 (has.sox@gmail.com)
# It's mainly just adding vowels, as I ht cd wth n vwls :)
# This represents the hard part of the work, all I did was change the
# underlying parser.
class REXMLUtilityNode # :nodoc:
  attr_accessor :name, :attributes, :children, :type
  cattr_accessor :typecasts, :available_typecasts
  
  self.typecasts = {}
  self.typecasts["integer"]       = lambda{|v| v.nil? ? nil : v.to_i}
  self.typecasts["boolean"]       = lambda{|v| v.nil? ? nil : (v.strip != "false")}
  self.typecasts["datetime"]      = lambda{|v| v.nil? ? nil : Time.parse(v).utc}
  self.typecasts["date"]          = lambda{|v| v.nil? ? nil : Date.parse(v)}
  self.typecasts["dateTime"]      = lambda{|v| v.nil? ? nil : Time.parse(v).utc}
  self.typecasts["decimal"]       = lambda{|v| BigDecimal(v)}
  self.typecasts["double"]        = lambda{|v| v.nil? ? nil : v.to_f}
  self.typecasts["float"]         = lambda{|v| v.nil? ? nil : v.to_f}
  self.typecasts["symbol"]        = lambda{|v| v.to_sym}
  self.typecasts["string"]        = lambda{|v| v.to_s}
  self.typecasts["yaml"]          = lambda{|v| v.nil? ? nil : YAML.load(v)}
  self.typecasts["base64Binary"]  = lambda{|v| Base64.decode64(v)}
  
  self.available_typecasts = self.typecasts.keys

  def initialize(name, attributes = {})
    @name         = name.tr("-", "_")
    # leave the type alone if we don't know what it is
    @type         = self.class.available_typecasts.include?(attributes["type"]) ? attributes.delete("type") : attributes["type"]
    
    @nil_element  = attributes.delete("nil") == "true"
    @attributes   = undasherize_keys(attributes)
    @children     = []
    @text         = false
  end

  def add_node(node)
    @text = true if node.is_a? String
    @children << node
  end

  def to_hash
    if @type == "file"
      f = StringIO.new(::Base64.decode64(@children.first || ""))  
      class << f
        attr_accessor :original_filename, :content_type
      end
      f.original_filename = attributes['name'] || 'untitled'
      f.content_type = attributes['content_type'] || 'application/octet-stream'
      return {name => f}
    end
    
    if @text
      return { name => typecast_value( translate_xml_entities( inner_html ) ) }
    else
      #change repeating groups into an array
      groups = @children.inject({}) { |s,e| (s[e.name] ||= []) << e; s }
      
      out = nil
      if @type == "array"
        out = []
        groups.each do |k, v|
          if v.size == 1
            out << v.first.to_hash.entries.first.last
          else
            out << v.map{|e| e.to_hash[k]}
          end
        end
        out = out.flatten
        
      else # If Hash
        out = {}
        groups.each do |k,v|
          if v.size == 1
            out.merge!(v.first)
          else
            out.merge!( k => v.map{|e| e.to_hash[k]})
          end
        end
        out.merge! attributes unless attributes.empty?
        out = out.empty? ? nil : out
      end

      if @type && out.nil?
        { name => typecast_value(out) }
      else
        { name => out }
      end
    end
  end

  # Typecasts a value based upon its type. For instance, if
  # +node+ has #type == "integer",
  # {{[node.typecast_value("12") #=> 12]}}
  #
  # ==== Parameters
  # value<String>:: The value that is being typecast.
  # 
  # ==== :type options
  # "integer":: 
  #   converts +value+ to an integer with #to_i
  # "boolean":: 
  #   checks whether +value+, after removing spaces, is the literal
  #   "true"
  # "datetime"::
  #   Parses +value+ using Time.parse, and returns a UTC Time
  # "date"::
  #   Parses +value+ using Date.parse
  #
  # ==== Returns
  # Integer, true, false, Time, Date, Object::
  #   The result of typecasting +value+.
  #
  # ==== Note
  # If +self+ does not have a "type" key, or if it's not one of the
  # options specified above, the raw +value+ will be returned.
  def typecast_value(value)
    return value unless @type
    proc = self.class.typecasts[@type]
    proc.nil? ? value : proc.call(value)
  end

  # Convert basic XML entities into their literal values.
  #
  # ==== Parameters
  # value<~gsub>::
  #   An XML fragment.
  #
  # ==== Returns
  # ~gsub::
  #   The XML fragment after converting entities.
  def translate_xml_entities(value)
    value.gsub(/&lt;/,   "<").
          gsub(/&gt;/,   ">").
          gsub(/&quot;/, '"').
          gsub(/&apos;/, "'").
          gsub(/&amp;/,  "&")
  end

  # Take keys of the form foo-bar and convert them to foo_bar
  def undasherize_keys(params)
    params.keys.each do |key, value|
      params[key.tr("-", "_")] = params.delete(key)
    end
    params
  end

  # Get the inner_html of the REXML node.
  def inner_html
    @children.join
  end

  # Converts the node into a readable HTML node.
  #
  # ==== Returns
  # String:: The HTML node in text form.
  def to_html
    attributes.merge!(:type => @type ) if @type
    "<#{name}#{attributes.to_xml_attributes}>#{@nil_element ? '' : inner_html}</#{name}>"
  end

  # ==== Alias
  # #to_html
  def to_s 
    to_html
  end
end

class ToHashParser # :nodoc:

  def self.from_xml(xml)
    stack = []
    parser = REXML::Parsers::BaseParser.new(xml)
    
    while true
      event = parser.pull
      case event[0]
      when :end_document
        break
      when :end_doctype, :start_doctype
        # do nothing
      when :start_element
        stack.push REXMLUtilityNode.new(event[1], event[2])
      when :end_element
        if stack.size > 1
          temp = stack.pop
          stack.last.add_node(temp)
        end
      when :text, :cdata
        stack.last.add_node(event[1]) unless event[1].strip.length == 0
      end
    end
    stack.pop.to_hash
  end
end
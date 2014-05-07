def load_current_resource
  require 'resolv'
  
  @current_resource = Chef::Resource::Route53Record.new(@new_resource.name)
  @current_resource.name(@new_resource.name)
  @current_resource.type(@new_resource.type)
  @current_resource.value(@new_resource.value)
  @current_resource.alias_target(@new_resource.alias_target)
  
  resource_classes = {  'A' => Resolv::DNS::Resource::IN::A,
                        'AAAA' => Resolv::DNS::Resource::IN::AAAA,
                        'CNAME' => Resolv::DNS::Resource::IN::CNAME,
                        'MX' => Resolv::DNS::Resource::IN::MX,
                        'NS' => Resolv::DNS::Resource::IN::NS,
                        'PTR' => Resolv::DNS::Resource::IN::PTR,
                        'SOA' => Resolv::DNS::Resource::IN::SOA,
                        'TXT' => Resolv::DNS::Resource::IN::TXT,
                        'SRV' => Resolv::DNS::Resource::IN::SRV,
                        'SPF' => Resolv::DNS::Resource::IN::SRV }
  
  begin
    record = Resolv::DNS.new.getresource( @current_resource.name , resource_classes[@current_resource.type] )
  
    @current_resource.exists = case @current_resource.type
    when 'CNAME'
      record.name.to_s == @current_resource.alias_target ? true : false
    else
      record.address.to_s == @current_resource.value ? true : false
    end
  rescue Resolv::ResolvError
    @current_resource.exists = false
  end
  
end

action :create do

  unless @current_resource.exists

    require 'fog/aws/dns'
    require 'nokogiri'
  
    def aws
      {
      :provider => 'AWS',
      :aws_access_key_id => new_resource.aws_access_key_id,
      :aws_secret_access_key => new_resource.aws_secret_access_key
      }
    end
  
    def name
      @name ||= new_resource.name + "."
    end
  
    def value
      @value ||= Array(new_resource.value)
    end
  
    def type
      @type ||= new_resource.type
    end
  
    def ttl
      @ttl ||= new_resource.ttl
    end
  
    def overwrite
      @overwrite ||= new_resource.overwrite
    end
  
    def alias_target
      @alias_target ||= new_resource.alias_target
    end
  
    def zone(connection_info)
      if new_resource.aws_access_key_id && new_resource.aws_secret_access_key
        zones = Fog::DNS.new(connection_info).zones
      else
        Chef::Log.info "No AWS credentials supplied, going to attempt to use IAM roles instead"
        zones = Fog::DNS.new({ :provider => "AWS", :use_iam_profile => true }
                               ).zones
      end
      
      if new_resource.zone_id
        myzone = zones.get( new_resource.zone_id )
        @name = name + myzone.domain.chop unless name.match(myzone.domain.chop)
        myzone
      else
        myzone = Array.new
        domain = new_resource.name.split('.')
  
        until myzone.count != 0 do
          domain.shift
          domainstr = domain.join('.')
          myzone = zones.select { |z| z.domain.match(domainstr)}
        end
  
        if myzone.count == 1
          myzone[0]
        else
          raise ArgumentError.new('ZoneID not provided and unable to determine zone')
        end
      end
    end
  
    def create
      begin
        zone(aws).records.create(record_attributes)
      rescue Excon::Errors::BadRequest => e
        Chef::Log.error Nokogiri::XML( e.response.body ).xpath( "//xmlns:Message" ).text
      end
    end
  
    def record_attributes
      common_attributes = { :name => name, :type => type }
      common_attributes.merge(record_value_or_alias_attributes)
    end
  
    def record_value_or_alias_attributes
      if alias_target
        { :alias_target => alias_target.to_hash }
      else
        { :value => value, :ttl => ttl }
      end
    end
  
    def same_record?(record)
      name.eql?(record.name) &&
        same_value?(record)
    end
  
    def same_value?(record)
      if alias_target
        same_alias_target?(record)
      else
        value.sort == record.value.sort
      end
    end
  
    def same_alias_target?(record)
      alias_target &&
        record.alias_target &&
        (alias_target['dns_name'] == record.alias_target['DNSName'].gsub(/\.$/,''))
    end
  
    record = zone(aws).records.get(name, type)
  
    if record.nil?
      create
      Chef::Log.info "Record created: #{name}"
    elsif !same_record?(record)
      unless overwrite == false
        record.destroy
        create
        Chef::Log.info "Record modified: #{name}"
     else
        Chef::Log.info "Record #{name} should have been modified, but overwrite is set to false."
        Chef::Log.debug "Current value: #{record.value.first}"
        Chef::Log.debug "Desired value: #{value}"
      end
    else Chef::Log.info "There is nothing to update."
    end
  else
    Chef::Log.info "Record exists"
  end
end

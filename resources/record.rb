actions :create

default_action :create

attribute :name,                  :kind_of => String , :required => true
attribute :value,                 :kind_of => [ String, Array ]
attribute :type,                  :kind_of => String, :required => true , :equal_to => [ "A" , "AAAA" , "MX" , "SOA" , "SPF" , "CNAME" , "TXT" , "PTR" , "SRV" , "NS" ]
attribute :ttl,                   :kind_of => Integer, :default => 3600
attribute :zone_id,               :kind_of => String
attribute :aws_access_key_id,     :kind_of => String
attribute :aws_secret_access_key, :kind_of => String
attribute :overwrite,             :kind_of => [ TrueClass, FalseClass ], :default => true
attribute :alias_target,          :kind_of => Hash

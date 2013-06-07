require 'fog'
    
class Chef::Recipe::DNS
  
  def self.updateDNS(hostname, domain, ipv4adr, ec2_access)
    
    hostname.downcase!
    
    dns = Fog::DNS.new(:provider => "AWS",
      :aws_access_key_id => ec2_access["aws_access_key_id"],
      :aws_secret_access_key => ec2_access["aws_secret_access_key"]
      )
      
    zoneResponse = dns.list_hosted_zones()
    
    # zoneResponse.each { |z|
    #  puts z
    #}
    
    origin = domain
    origin = "dns_root_zone_not_set." if origin == nil
    newipadr = ipv4adr
    fqhostname = origin
    fqhostname = hostname + "." + origin if hostname != ""

    the_zone = nil
    
    dns.zones.each { |zone|
      if(zone.domain == origin)
    	  the_zone = zone	
      end  
    }
        
    if !the_zone.nil?
      aws_records = the_zone.records.select{|record| record.type != "SOA" and record.type != "NS" and record.type != "MX" }
      puts "Records in AWS Zone #{the_zone.id}:"
 
      if(aws_records.nil? or aws_records.empty?)
    	    puts "Empty"
      end 

      change_batch_deleted_hash = {}
 
      aws_records.each { |record|
        if record.name == fqhostname
            #puts record.to_yaml
            if record.respond_to? :value  ## handle both api versions
              puts "#{record.name} #{record.ttl} IN #{record.type} #{record.value}"
              return if record.value[0] == newipadr
              rr = record.attributes.delete(:value)
            else
              puts "#{record.name} #{record.ttl} IN #{record.type} #{record.ip}"
              return if record.ip[0] == newipadr 
              rr = record.attributes.delete(:ip)
            end              
            change_delete = {:action => 'DELETE'}.merge(record.attributes.merge({:resource_records => rr}))
            change_batch_deleted_hash["#{record.name.downcase}-#{record.type}"] = change_delete
        end
      }

      change_batch_created_hash = {}
      change_create = {:action => 'CREATE', :name => fqhostname, :type => "A", :ttl => 120, :resource_records => ([]<<"#{newipadr}")}
      change_batch_created_hash["#{change_create[:name].to_s}.-#{change_create[:type]}"] = change_create
      
      change_batch = change_batch_deleted_hash.values.concat(change_batch_created_hash.values.select{|change| change[:type] != "SOA" and change[:type] != "NS" and change[:type] != "MX"})
      
      change_batch.each{|change|
         puts "updating: #{change.inspect}"
      }
   	  
   	  dns.change_resource_record_sets(the_zone.id, change_batch, {"comment" => "updated by chef recipe"})

   	  puts "Zone Updated: "
   	  the_zone.inspect
    else
      puts "FAILED TO FIND ZONE - " + origin
    end
  end
end

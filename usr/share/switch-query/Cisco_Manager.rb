require 'net/telnet'
require 'net/ssh'

class Cisco_Manager
    attr_accessor :protocol, :hostname, :password, :enablepassword, :MacSize

    def initialize(protocol:, hostname:, password:, enablepassword:)
        @hostname = hostname
        @password = password
        @enablepassword = enablepassword
        @protocol = protocol
        @MacSize = 0

        if @protocol == "ssh"
            init_ssh(hostname: @hostname,password: @password, enablepassword: @enablepassword)
        elsif @protocol == "telnet"
            init_telnet(hostname: @hostname,password: @password, enablepassword: @enablepassword)
        else 
            raise "Error! Protocol must be either 'ssh' or 'telnet'"
        end
    end

    def init_ssh(hostname:,password:,enablepassword:)
        @ssh_con = NET::SSH.start(hostname,username,password,enablepassword)
        @ssh_con.exec!("terminal length 0")
    end

    def init_telnet(hostname:,password:,enablepassword:)
        # puts "starting telnet"
        @tn = Net::Telnet.new(
            # "Dump_log" => "/dev/stdout",
            "Host" => hostname,
            "Prompt" => /^.*[>#(Password:.*)]$/,
            "TimeOut" => 100
        )
        @tn.binmode = true
        @tn.waitfor(/.*Password:.*/)
        @tn.cmd(@password)
        @tn.cmd("terminal length 0")
    end


    def enable
        @tn.cmd({"String" => "enable"})
        @tn.waitfor(/.*Password:/i)
        @tn.cmd(@enablepassword)
    end

    def close()
        @tn.close
    end
  
    def get_uptime# [years,weeks,days,hours,mins]
      array = {:Years => 0,:Weeks => 0,:Days => 0,:Hours => 0,:Minutes => 0}
      @tn.cmd("show version | include uptime") # for some reason i had to shift everything to a cmd and waitfor connection.... 
      @tn.waitfor(/min/i) do |a|
        # print a.split
        a.split(",").each do |item|
            item = item.gsub(/.*is/,"")
            item = item.gsub(/\n.*/,"")
            array.store :Years,   item.gsub(/[^0-9]/,"") if item =~ /.*\d+\s+year[s]*/
            array.store :Weeks,   item.gsub(/[^0-9]/,"") if item =~ /.*\d+\s+week[s]*/
            array.store :Days,    item.gsub(/[^0-9]/,"") if item =~ /.*\d+\s+day[s]*/
            array.store :Hours,   item.gsub(/[^0-9]/,"") if item =~ /.*\d+\s+hour[s]*/
            array.store :Minutes, item.gsub(/[^0-9]/,"") if item =~ /.*\d+\s+minute[s]*/
        end
      end
      array
    end

    def get_uptime_ssh # [weeks,days,hours,mins]
        array = {:Years => 0,:Weeks => 0,:Days => 0,:Hours => 0,:Minutes => 0}
        @ssh_con.exec!("show version | include uptime") do |a|
          # print a.split
          a.split(",").each do |item|
              item = item.gsub(/.*is/,"")
              item = item.gsub(/\n.*/,"")
              array.store :Years,   item.gsub(/[^0-9]/,"") if item =~ /.*\d+\s+year[s]*/
              array.store :Weeks,   item.gsub(/[^0-9]/,"") if item =~ /.*\d+\s+week[s]*/
              array.store :Days,    item.gsub(/[^0-9]/,"") if item =~ /.*\d+\s+day[s]*/
              array.store :Hours,   item.gsub(/[^0-9]/,"") if item =~ /.*\d+\s+hour[s]*/
              array.store :Minutes, item.gsub(/[^0-9]/,"") if item =~ /.*\d+\s+minute[s]*/
          end
        end
        array
    end
    

    def get_mac_table()
        array = []
        @tn.cmd({"String" => "show mac-address-table","Timeout" => 100}) do |table|
        # @tn.waitfor(/criterion/) do |table|
            reg = /\d+\s+([a-fA-F0-9]{4}\.{0,1}){3}\s+[A-Z]+\s+(Fa|Gi|Te)(\d\/)*(\d+)/
            # puts table
            table.split("\n").each do |line|
                if reg =~ line
                    array << line.split(" ").each {|a| a.strip!()}
                end
            end
        end
        @MacSize = array.count
        array
    end

    def get_mac_table2()  # depending on cisco ios version you may have "show mac-address-table" or "show mac address-table"
        array = []
        @tn.cmd({"String" => "show mac address-table", "Timeout" => 100})
        @tn.waitfor(/criterion/) do |table|
            reg = /\d+\s+([a-fA-F0-9]{4}\.{0,1}){3}\s+[A-Z]+\s+(Fa|Gi|Te)(\d\/)*(\d+)/
            # puts table
            table.split("\n").each do |line|
                if reg =~ line
                    array << line.split(" ").each {|a| a.strip!()}
                end
            end
        end
        @MacSize = array.count
        array
    end

    def get_vlan_brief
        array = []
        @tn.cmd "show vlan brief"
        @tn.waitfor(/default/) do |br|
            br.gsub! /VLAN|Name|Status|Ports/,""
            br.gsub! /-/, ""
            br = br.gsub( /\r\n(?=\s)/ , "").gsub(/\r/,"").gsub(/,/,"")
            br.split("\n").each do |line|
                if line.strip == ""
                    next
                end
                vlan = {}
                ports = []
                # print line.split(" ")
                line.split(" ").each do |item|
                    item.strip!
                    if item[0] =~ /\d+/ 
                        vlan.store "Vlan",item
                    elsif item =~ /[FaGiTe]{2}\d(\/\d+){1,2}/
                        ports << item
                    elsif item =~ /active|dissabled|act\/unsup/
                        vlan.store "Status",item
                    elsif item =~ /[a-zA-Z0-9\-\&\_]*/ 
                        vlan.store "Name",item
                    end
                end
                vlan.store "Ports", ports 
                array << vlan 
            end
        end
        array.delete_if { |h| h["Vlan"] == nil}
    end

    def get_name_servers
        array = []
        @tn.cmd({"String" => 'show hosts | include Name server'} ) 
        @tn.waitfor(/are/) do |servers| 
            servers.split("\n").each do |line| 
                if /Name serv/ =~ line
                    line.gsub(/[a-zA-Z\s]/, "").split(',').each do |ip| 
                        array << ip 
                    end
                end
            end
        end
        array 
    end

    def get_throughput_hash
        array = [] 
        @tn.cmd({"String" => "show interface summary"}) 
        @tn.waitfor(/Details/) do |table|
            reg = /\*{0,1}\s+[a-zA-Z0-9\/]+(\s+\d+){9}/
            table.split("\n").each do |line| 
                if reg =~ line 
                    array << line.split(" ").each {|a| a.strip!()}
                end
            end
        end
        array.each do |host|
            if host[0] != "*"
                host.unshift(" ")
            end
        end
        array.map {|_Status,_Interface,_IHQ,_IQD,_OHQ,_OQD,_RXBS,_RXPS,_TXBS,_TXPS,_TRTL| {Status: _Status,Interface: _Interface,IHQ: _IHQ,IQD: _IQD,OHQ: _OHQ,OQD: _OQD,RXBS: _RXBS,RXPS: _RXPS,TXBS: _TXBS,TXPS: _TXBS,TRTL: _TRTL} }
    end

    def get_throughput 
        h = get_throughput_hash
        tx = 0
        rx = 0
        h.each do |i| 
            tx += i[:TXBS].to_i
            rx += i[:RXBS].to_i
        end
        [tx,rx]
        
    end

    def get_interfaces 
        ar = []
        @tn.cmd({"String" => "show run"}) # this is a long running command... have to use wait for or the telnet session will die
        @tn.waitfor(/.*end.*/) do |run| 
            sleep 1   # not sure wahts going on but if you sleep for a second all the data seems to populate.... hmmm
            lines = run.split "\n"

            lines.each_with_index do |line,index| 
                hash = {}

                if line =~ /interface/i
                    hash[:interface] = line.split(' ').last
                    i = 1;
                    until lines[index+i].strip() == "!" do
                        if lines[index+i] =~ /mode/i
                            hash[:interface_mode] = lines[index+i].split(' ').last
                        elsif lines[index+i] =~ /description/i
                            tmp = lines[index+i].split(' ')
                            tmp.delete "description"
                            hash[:description] = tmp.join(' ')
                        elsif lines[index+i] =~ /access/i
                            tmp = lines[index+i].split(' ')
                            tmp.delete "switchport"
                            tmp.delete "vlan"
                            tmp.delete "access"
                            hash[:vlans] = tmp.each do |vl| vl = vl.to_i end

                        end

                        i+=1

                    end

                end
                puts hash unless hash.empty?
                ar << hash unless hash.empty?
            end
        end
        ar = []
    end

    # def get_time
    #     Time
    # end
end
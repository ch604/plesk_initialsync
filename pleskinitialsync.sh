#!/bin/bash
#Plesk migration script
#by awalilko@liquidweb.com
#many thanks to abrevick@lw for his cpanel initialsync script, off of which this was based.
ver='jun.18.13'
#=========================================================
#initial setup and global variables
#==================================

test -f /var/didnotrestore.txt && mv /var/didnotrestore.txt{,.`date +%F.%T`.bak}
didnotrestore=/var/didnotrestore.txt
tmpfolder=/var/migrationtemp
logfile=$tmpfolder/migrationlog.txt

yesNo() { #generic yesNo function 
#repeat if yes or no option not valid
while true; do
#$* read every parameter giving to the yesNo function which will be the message
 echo -ne "${yellow}${*}${white} (Y/N)? ${noclr}"
 #junk holds the extra parameters yn holds the first parameters
 read yn junk
 case $yn in
  yes|Yes|YES|y|Y)
    return 0  ;;
  no|No|n|N|NO)
    return 1  ;;
  *)
    echo -e "Please enter y or n."
 esac
done
}

red='\e[1;31m'
green='\e[1;32m'
yellow='\e[1;33m'
blue='\e[1;34m'
purple='\e[1;35m'
white='\e[1;37m'
noclr='\e[0m'

#========
#end init
#========

main() {
mainloop=0
clear
while [ $mainloop == 0 ]; do
 echo -e "${white}Welcome to the Plesk Migration Tool!
Version: $ver${noclr}
This tool has been tested on Plesk 8+. ymmv."
 if [[ ! "${STY}" ]]; then
  echo -e "${red}
!!!!!
You are not in a screen session. Please run this script in a screen session!
!!!!!1${noclr}"
 fi
 echo -e "
${white}Select your migration type:${noclr}
 A) Help!
 1) Full initial sync (all plesk accounts and all data, one backup file)
 2) Client list sync (from /var/userlist.txt)
 3) Domain list sync (from /var/domainlist.txt)
 4) Full update sync (all homedirs, databases, and mail files)
 5) Client list update sync (as 4, but from /var/userlist.txt)
 6) Domain list update sync (as 4, but from /var/domainlist.txt)
 7) Generate a list of clients for this server to /var/clientlist.txt (to help you make /var/userlist.txt)
 8) Generate a list of subscriptions for this server to /var/sublist.txt (to help you make /var/domainlist.txt)
 9) Final sync (all domains, databases, and mail files)
 0) Quit
"
 echo -e "${white}Enter your choice:${noclr}"
 read choice
 case $choice in
  A|a)
   clear
   echo -e "This tool is designed to migrate data between plesk servers. For most migrations, you will want to use the full initial sync followed by the final sync at a later time after testing is complete. If you need more granularity in syncing (for example, if you are copying one or two clients or one or two domains for a particular client), then you can use the client list sync or domain list sync. It is recommended, if you use either of these two options, to use the client sync, as this will bring across client-level data, which the domain list sync does not. However, if you need to migrate one domain and the client owns more than one domain, the domain list sync will work well for this.

Now for the tl;dr:

The presync functions encompass checking for common third-party applications, downgrading from php 5.3 to php 5.2 if neccessary, lowering the TTL values for hosted DNS, setting up SSH keys, and other important prep tasks for all migrations.

The full sync works by creating a configuration-only backup of the entire server and restoring this on the target. Obviously, this works best with an empty target server. Then, individual domains are synced at a folder level to the target server, the mail folders are copied, and databases are dumped and reimported. The final sync for this task redumps all the databases and updates the folder syncs, then changes the DNS on the old server to match the new server.

The client list sync takes a list of clients and makes client-level configuration backups. These are restored one at a time on the target server, and then databases are dumped and copied, and folders are synced. At the end of the client list loop, the databases are imported on the target server.

The domain list sync works as the client list sync does, but at a subscription-level backup. 

After all types of syncs, the target server is checked for accounts that did not restore correctly, and a list of hosts file entries is generated.

Press enter to return to the menu."
  read
  clear;;
  1)
   initialsync
   mainloop=1;;
  2)
   clientlistsync
   mainloop=1;;
  3)
   domainlistsync
   mainloop=1;;
  4)
   updatesync
   mainloop=1;;
  5)
   clientlistupdatesync
   mainloop=1;;
  6)
   domainlistupdatesync
   mainloop=1;;
  7)
   echo -e "One moment..."
   sleep 1
   mysql psa -u admin -p$(cat /etc/psa/.psa.shadow) -Ns -e 'SELECT c.login, d.name FROM clients AS c JOIN domains AS d ON d.cl_id = c.id;' > /var/clientlist.txt
   clear
   echo -e "${yellow}A list of clients on this server was placed in /var/clientlist.txt.${noclr}"
   sleep 2;;
  8)
   echo -e "One moment..."
   sleep 1
   mysql psa -u admin -p$(cat /etc/psa/.psa.shadow) -Ns -e 'SELECT name FROM domains JOIN Subscriptions ON Subscriptions.object_id = domains.id;' > /var/sublist.txt
   clear
   echo -e "${yellow}A list of subscriptions on this server was placed in /var/sublist.txt.${noclr}"
   sleep 2;;
  9) 
   finalsync
   mainloop=1;;
  0)
   echo -e "Quitting, quitter!"
   exit 0;;
  *)
   echo -e Please select a valid migration type.
   sleep 2
   clear
 esac
done
echo -e Finished!
exit 
}

initialsync() {
echo -e "${purple}Starting full initial sync.${noclr}"
presync
domainexistcheck
createbackup
syncbackup
ipmaptool
restore
dnrcheck
hostsfile
removekey
}

clientlistsync() {
clientlistfile=/var/userlist.txt
echo -e "${purple}Syncing from $clientlistfile:${noclr}
"
cat $clientlistfile
if yesNo "This look good to you?"; then
clientcheck
presync
didnotbackup=/var/didnotbackup.txt
syncclients
dnrcheck
hostsfile
removekey
else
echo -e "${red}Check yoself before you wreck yoself. Quitting.${noclr}"
exit 0
fi
}

domainlistsync() {
domlistfile=/var/domainlist.txt
echo -e "${purple}Syncing from $domlistfile:${noclr}
"
cat $domlistfile
if yesNo "This look good to you?"; then
subcheck
presync
didnotbackup=/var/didnotbackup.txt
syncdomains
dnrcheck
hostsfile
removekey
else
echo -e "${red}Check yoself before you wreck yoself. Quitting.${noclr}"
exit 0
fi
}

presync() {
echo -e "${purple}Starting pre-backup tasks.${noclr}"
dnscheck
rsyncupgrade
lowerttls
getip
foldersetup
licensecheck
ipcheck
phpupgrade
autoinstaller
}

updatesync() {
echo -e "${purple}Starting full update sync.${noclr}"
rsyncupgrade
getip
databasefinalsync
rsynchomedirs
rsyncemail
removekey
}

clientlistupdatesync() {
echo -e THIS IS NOT READY YET
exit 0
}

domainlistupdatesync() {
echo -e THIS IS NOT READY YET
exit 0
}

#================
#start final sync
#================

finalsync() {
echo -e "${purple}Starting final sync.${noclr}"

#get options for final sync
getip
if yesNo "Stop services for final sync?"; then
 stopservices=1
 if yesNo "Restart services after final sync?"; then
  restartservices=1
 fi
fi

if yesNo 'Copy DNS information from target PSA database? Do not do this unless migrating all users, and DNS is on the local machine.'; then
 copydns=1
fi

echo -e Press enter to begin the final sync!
read

rsyncupgrade

#stop services
if [ $stopservices ]; then
 echo -e "${white}Stopping Services...${noclr}"
 /etc/init.d/httpd stop
 /etc/init.d/qmail stop
 /etc/init.d/exim stop
else
 echo -e "${white}Not stopping services...${noclr}"
fi

#do the sync
databasefinalsync
finalrsynchomedirs
rsyncemail

#copy the dns info back
if [ $copydns ]; then
 echo -e "${white}Copying zone file information over from new server...${noclr}"
 if [ `ssh -q $target -p$port "ls $tmpfolder/ | grep ^mapfile.txt$"` ]; then
  rsync -avHPe "ssh -q -p$port" $target:$tmpfolder/mapfile.txt $tmpfolder/
  mv /var/named/chroot/etc/named.conf{,.`date +%F.%T`.bak}
  cp -a /var/named/chroot/etc/named.conf{.default,} #this fixes some errors with named not starting after final sync.
  cat $tmpfolder/mapfile.txt | grep "\->" | awk '{print "mysql psa -u admin -p$(cat /etc/psa/.psa.shadow) -D psa -e \"UPDATE dns_recs SET val=\\\""$1"\\\", displayVal=\\\""$1"\\\" WHERE val=\\\""$4"\\\"\""}' | sh
  mysql psa -u admin -p$(cat /etc/psa/.psa.shadow) -Ns -e 'SELECT name FROM domains' | awk '{print "/usr/local/psa/admin/sbin/dnsmng update " $1 }' | sh
  /etc/init.d/named restart
 else
  echo -e "${red}The IP mapping file ${white}($tmpfolder/mapfile.txt)${red} was not found on the target server! please update the DNS records on your own!${noclr}"
  sleep 3
  mapfilefail=1
 fi
fi

#restart services
if [ $restartservices ]; then
 echo -e "${white}Restarting services...${noclr}"
 /etc/init.d/httpd start
 /etc/init.d/qmail start
 /etc/init.d/exim start
else
 echo -e "${white}Skipping restart of services...${noclr}"
fi

#display mysqldump errors
if [ -s /tmp/mysqldump.log ]; then
 echo -e 
 echo -e "${red}Errors detected during mysqldumps:${noclr}"
 cat /tmp/mysqldump.log
 echo -e "${red}End of errors from /tmp/mysqldump.log.${noclr}"
 sleep 1
fi

echo -e '${green}Final sync complete, check the screen "dbsync" on the remote server to ensure all databases imported correctly.${noclr}'
if [ $mapfilefail ]; then
 echo -e "${red}The mapfile on the target server could not be found! Please remember to update DNS!${noclr}"
fi
removekey
}

databasefinalsync() { #perform just a database sync, reimporting on the target side.
echo -e "${white}Dumping the databases...${noclr}"
test -d $tmpfolder/dbdumps && mv $tmpfolder/dbdumps{,.`date +%F.%T`.bak}
mkdir -p $tmpfolder/dbdumps
ssh -q $target -p$port 'test -d $tmpfolder/dbdumps && mv $tmpfolder/dbdumps{,.`date +%F.%T`.bak}'
mysqldumpver=`mysqldump --version |cut -d" " -f6 |cut -d, -f1`
for db in `mysql -u admin -p$(cat /etc/psa/.psa.shadow) -Ns -e "show databases" | egrep -v "^(psa|mysql|horde|information_schema|phpmyadmin.*)$"`; do
 mysqldumpfunction
done

#move the dumps to the new server
rsync -avHlPze "ssh -q -p$port" $tmpfolder/dbdumps $target:$tmpfolder/

#start import of databases in screen on target
dbsyncscript
}

mysqldumpfunction() { #argument is 'db' provided by a loop
echo -e "Dumping $db"
if [[ $mysqldumpver < 5.0.42 ]]; then
 mysqldump -u admin -p$(cat /etc/psa/.psa.shadow) --add-drop-table $db > $tmpfolder/dbdumps/$db.sql
 mysqldump -u admin -p$(cat /etc/psa/.psa.shadow) --force --add-drop-table --log-error=/tmp/mysqldump.log $db > $tmpfolder/dbdumps/$db.sql
fi
}

dbsyncscript () { #create a script to restore the databases on the target server, then run it there in a screen
cat > /var/dbsync.sh <<'EOF'
#!/bin/bash
#ran on remote server to sync dbs.
TMPFOLDER=/var/migrationtemp
LOG=$TMPFOLDER/dbdumps/dbdumps.log
if [ -d $TMPFOLDER/dbdumps ]; then
 cd $TMPFOLDER/dbdumps
 touch $LOG
 echo "Dump dated `date`" > $LOG
 #if the prefinalsyncdb directory exists, rename it
 test -d $TMPFOLDER/prefinalsyncdbs && mv $TMPFOLDER/prefinalsyncdbs{,.`date +%F.%R`.bak}
 mkdir $TMPFOLDER/prefinalsyncdbs
 for each in `ls *.sql|cut -d. -f1`; do
  echo "dumping $each" |tee -a $LOG
  (mysqldump -u admin -p$(cat /etc/psa/.psa.shadow) $each > $TMPFOLDER/prefinalsyncdbs/$each.sql) 2>>$LOG
  echo " importing $each" | tee -a $LOG
  (mysql -u admin -p$(cat /etc/psa/.psa.shadow) $each < $TMPFOLDER/dbdumps/$each.sql)  2>>$LOG
 done
 echo "Finished, hit a key to see the log."
 read
 less $LOG
else
 echo "$TMPFOLDER/dbdumps not found"
 read
fi
EOF
rsync -aHPe "ssh -q -p$port" /var/dbsync.sh $target:/var/
ssh -q $target -p$port "screen -S dbsync -d -m bash /var/dbsync.sh" &
echo -e "${white}Databases are importing in a screen on the target server. Be sure to check there to make sure they all imported OK.${noclr}"
sleep 2
}

rsynchomedirs() { #sync the docroots of all users, exluding the conf folder. the conf folder holds ip-specific data, which we do not want to migrate.
for each in `mysql -u admin -p$(cat /etc/psa/.psa.shadow) -Ns psa -e "select name from domains;"`; do
 if [ `ssh -q $target -p$port "ls /var/www/vhosts/ | grep ^$each$"` ]; then
  echo -e "${purple}Syncing data for ${white}$each${purple}...${noclr}"
  rsync -avHPe "ssh -q -p$port" /var/www/vhosts/$each root@$target:/var/www/vhosts/ --exclude=conf >> $logfile 2>&1
  rsync -avHPe "ssh -q -p$port" /var/www/vhosts/$each/httpdocs root@$target:/var/www/vhosts/$each/ --update >> $logfile 2>&1
 else
  echo -e "${red}$each did not restore remotely${noclr}"
  echo -e $each >> $didnotrestore
fi
done
}

finalrsynchomedirs() { #as with rsynchomedirs(), but without remote home check.
for each in `mysql -u admin -p$(cat /etc/psa/.psa.shadow) -Ns psa -e "select name from domains;"`; do
 echo -e "${purple}Syncing data for ${white}$each${purple}...${noclr}"
 rsync -avHPe "ssh -q -p$port" /var/www/vhosts/$each root@$target:/var/www/vhosts/ --update --exclude=conf >> $logfile 2>&1
 rsync -avHPe "ssh -q -p$port" /var/www/vhosts/$each/httpdocs root@$target:/var/www/vhosts/$each/ --update >> $logfile 2>&1
done
}

rsyncemail() { #rsync the whole mail folder
echo -e "${white}Syncing email...${noclr}"
rsync -avHPe "ssh -q -p$port" /var/qmail/mailnames/ root@$target:/var/qmail/mailnames/ --update >> $logfile 2>&1
}

#==============
#end final sync
#=================
#presync functions
#=================

dnscheck() { #check the current DNS settings based on the defined domain list
echo -e "${purple}Checking Current dns...${noclr}"
if [ -f /root/dns.txt ]; then
 echo -e "Found /root/dns.txt"
 sleep 3
 cat /root/dns.txt | sort -n +3 -2 | more
else
 yum -y install bind-utils
 domainlist=`mysql psa -u admin -p$(cat /etc/psa/.psa.shadow) -Ns -e 'select name from domains'`
 for each in $domainlist; do echo $each\ `dig @8.8.8.8 NS +short $each |sed 's/\.$//g'`\ `dig @8.8.8.8 +short $each` ; done | grep -v \ \ | column -t > /root/dns.txt
 cat /root/dns.txt | sort -n +3 -2 | more
fi
echo -e "${yellow}Enter to continue...${noclr}"
read
}

rsyncupgrade () { #upgrade rsync to v3.0 if not already there
RSYNCVERSION=`rsync --version |head -n1 |awk '{print $3}'`
rsyncmajor=`echo $RSYNCVERSION |cut -d. -f1`
if [[ $rsyncmajor -lt 3 ]]; then
 echo -e "${purple}Updating rsync...${noclr}"
 LOCALCENT=`cat /etc/redhat-release |awk '{print $3}'|cut -d '.' -f1`
 LOCALARCH=`uname -i`
 if [[ $LOCALCENT -eq 6 ]]; then
  rpm -Uvh http://migration.sysres.liquidweb.com//rsync/rsync-3.0.9-1.el6.rfx.$LOCALARCH.rpm
 else
  rpm -Uvh http://migration.sysres.liquidweb.com//rsync/rsync-3.0.0-1.el$LOCALCENT.rf.$LOCALARCH.rpm
 fi
else
 echo -e "${purple}Rsync already up to date.${noclr}"
fi
}

lowerttls() { #lower the TTLs of the DNS records in the psa database, and reload each domain through dnsmng
echo -e "${purple}Lowering TTL values on local server...${noclr}"
mysql psa -u admin -p$(cat /etc/psa/.psa.shadow) -e "insert into misc values ('soa_TTL','300');"
mysql psa -u admin -p$(cat /etc/psa/.psa.shadow) -e "update psa.dns_zone set ttl_unit=1, ttl=300;"
mysql psa -u admin -p$(cat /etc/psa/.psa.shadow) -Ns -e 'select name from domains' | awk '{print "/usr/local/psa/admin/sbin/dnsmng --update " $1 }' | sh
}

getip() { #determine if the target server variable exists from a previous migration
echo -e "${purple}Getting Ip for destination server...${noclr}"
#check for previous migration
ipfile=/root/dest.ip.txt
if [ -f $ipfile ]; then
 target=`cat $ipfile`
 echo -e "Ip from previous migration found: $target"
 getport
 if yesNo "Is $target the server you want?  Otherwise enter No to input new ip." ; then
  echo -e "Ok, continuing with $target"
  sshkeygen
 else
  rm -f /root/dest.port.txt
  ipask
 fi
else
 ipask
fi
sleep 1
}

ipask() { #get the target IP variable
echo -e
echo -n 'Enter destination server IP: ';
read target
echo $target > $ipfile
getport
sshkeygen
}

getport() { #get the target server ssh port
echo -e "Getting ssh port..."
if [ -s /root/dest.port.txt ]; then
 port=`cat /root/dest.port.txt`
 echo -e "Previous Ssh port found: $port"
else
 echo -n "Enter destination server SSH port [default 22]: "
 read port
fi
if [ -z $port ]; then
 echo -e "No port given, assuming 22"
 port=22
fi
echo $port > /root/dest.port.txt
}

sshkeygen() { #quietly create an ssh key if it does not exist and copy it to the remote server
echo -e "${purple}Generating SSH keys...${noclr}"
if ! [ -f ~/.ssh/id_rsa ]; then
 ssh-keygen -q -N "" -t rsa -f ~/.ssh/id_rsa
fi
echo -e "${purple}Copying key to remote server...${noclr}"
cat ~/.ssh/id_rsa.pub | ssh -q $target -p$port "cp -rp ~/.ssh/authorized_keys{,.syncbak} ; mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys"
ssh -q $target -p$port "echo \'Connected!\';  cat /etc/hosts| grep $target "
}

licensecheck() { #check the license of the target server to make sure it has enough domains in it
echo -e "${purple}Checking the target for a sufficiently permissive license key...${noclr}"
numdomains=`mysql -u admin -p$(cat /etc/psa/.psa.shadow) -Ns psa -e "select name from domains;" | wc -l`
targetlimdom=`ssh -q $target -p$port "/usr/local/psa/bin/keyinfo --list | grep lim_dom\:" | awk '{print $2}'`
echo -e "${white}Source server has $numdomains domains, target license permits $targetlimdom domains.${noclr}" | sed -e 's/\-1/unlimited/g'
if [[ $targetlimdom -eq -1 ]]; then
 echo -e "${green}Target license allows for unlimited domains, and can hold all these limes!${noclr}"
elif [[ $numdomains -le $targetlimdom ]]; then
 echo -e "${green}Target license seems to have a large enough key to hold all these limes.${noclr}"
else
 echo -e "${red}Target server probably cannot hold all these limes! Please upgrade target server license key!${noclr}"
fi
if yesNo "Continue with migration?"; then
 echo -e Carrying on...
else
 echo -e Do not want...
 exit 0
fi
}

ipcheck() { #check to ensure that there are the necessary number of IPs on the target machine
echo -e "${purple}Checking for a sufficient number of IPs...${noclr}"
shared=`/usr/local/psa/bin/ipmanage -l | grep " S " | wc -l`
exclusive=`/usr/local/psa/bin/ipmanage -l | grep " E " | wc -l`
targetshared=`ssh -q $target -p$port "/usr/local/psa/bin/ipmanage -l | grep ' S ' | wc -l"`
targetexclusive=`ssh -q $target -p$port "/usr/local/psa/bin/ipmanage -l | grep ' E ' | wc -l"`

#compare the number of ips on the source and the target machines
echo -e "
${white}On the source machine, there are $shared shared IPs and $exclusive exclusive IPs available.${noclr}"
if [[ $targetshared -ge $shared && $targetexclusive -ge $exclusive ]]; then
 echo -e "${white}There are also $targetshared shared IPs on the target machine, and $targetexclusive exclusive IPs. ${green}This seems like it will work.${noclr}"
else
 echo -e "${white}But, there are only $targetshared shared IPs and $targetexclusive exclusive IPs on the target machine. ${red}That doesn't seem like it will work.${noclr}"
fi
if yesNo "Do these numbers seem ok to you? Yes to continue, no to exit and recheck things before proceeding."; then
 echo -e Proceeding with migration.
else
 echo -e Exiting.
 exit 0
fi
}

autoinstaller() { #get plesk version on target machine and install pmm
echo -e "${purple}Installing PMM and other utilities on remote server...${noclr}"
ssh -q $target -p$port "/usr/local/psa/admin/bin/autoinstaller --select-release-current --install-component pmm --install-component horde --install-component mailman --install-component backup"
echo -e "${purple}Starting PMM install on the local server...${noclr}"
/usr/local/psa/admin/bin/autoinstaller --select-release-current --install-component pmm --install-component backup
}

phpupgrade() { #check for php 5.2.x and downgrade target if necessary.
echo -e "${purple}Checking for PHP 5.2.x...${noclr}"
phpvernum=`php -v | head -n1 | awk '{print $2}'`
tgphpvernum=`ssh -q $target -p$port "php -v" | head -n1 | awk '{print $2}'`
if [[ `echo $phpvernum | awk -F. '{print $1}'` -eq 5 && `echo $phpvernum | awk -F. '{print $2}'` -eq 2 ]]; then
 echo -e "${blue}PHP 5.2.x detected! Current version on source server is $phpvernum.${noclr}"
 echo -e "${blue}Current version on target server is $tgphpvernum.${noclr}"
 if yesNo "Downgrade php on target server?"; then
  echo -e "${purple}Downgrading php to 5.2.17 on target...${noclr}"
  ssh -q $target -p$port "rpm -qa | grep atomic |xargs rpm -e ; wget -q -O - http://www.atomicorp.com/installers/atomic.sh | sh "
  targetcent=`ssh -q $target -p$port "cat /etc/redhat-release" | awk '{print $3}' | cut -d. -f1`
  if [ $targetcent == 6 ]; then
   ssh -q $target -p$port "yum -y downgrade php-5.2.17-1.el6.art.x86_64 php-cli-5.2.17-1.el6.art php-common-5.2.17-1.el6.art php-devel-5.2.17-1.el6.art php-gd-5.2.17-1.el6.art php-imap-5.2.17-1.el6.art php-ncurses-5.2.17-1.el6.art php-mcrypt-5.2.17-1.el6.art php-mbstring-5.2.17-1.el6.art php-mysql-5.2.17-1.el6.art php-pdo-5.2.17-1.el6.art php-xml-5.2.17-1.el6.art php-pear php-snmp-5.2.17-1.el6.art php-xmlrpc-5.2.17-1.el6.art; yum -y install php-devel-5.2.17-1.el6.art; /etc/init.d/httpd restart"
  elif [ $targetcent == 5 ]; then
   ssh -q $target -p$port "yum -y install php-5.2.17-1.el5.art.x86_64 php-common-5.2.17-1.el5.art php-gd-5.2.17-1.el5.art php-imap-5.2.17-1.el5.art php-mbstring-5.2.17-1.el5.art php-mysql-5.2.17-1.el5.art php-pdo-5.2.17-1.el5.art php-xml-5.2.17-1.el5.art; /etc/init.d/httpd restart"
  else
   echo -e"{$red}Could not determine target OS version! Update this script or use a real OS!${noclr}"
  fi
  echo -e "${purple}Target server is now using PHP `ssh -q $target -p$port "php -v" | head -n1 | awk '{print $2}'`.${noclr}"
 else
  echo -e Keeping target version at $tgphpvernum.
 fi
else
 echo -e PHP 5.2.x not detected.
fi
}

foldersetup() { #set up tmpfolder on both servers
test -d $tmpfolder && mv $tmpfolder{,.`date +%F.%T`.bak}
mkdir -p $tmpfolder/dbdumps
ssh -q -p$port root@$target "test -d $tmpfolder && mv $tmpfolder{,.`date +%F.%T`.bak}"
ssh -q -p$port root@$target "mkdir $tmpfolder"
}

#===================
#end presync scripts
#===================
#start regular sync
#==================

domainexistcheck() { #make sure that domains that exist on the source do not already have a folder on the target
echo -e "${purple}Checking for coincidental domains on target server...${noclr}"
catpreexisting=0
for each in `mysql -u admin -p$(cat /etc/psa/.psa.shadow) -Ns psa -e "select name from domains;"`; do
 if [ `ssh -q $target -p$port "ls /var/www/vhosts/ | grep ^$each$"` ]; then
  echo $each >> /root/preexisting.txt
  catpreexisting=1
 fi
done
if [[ $catpreexisting -eq 1 ]]; then
 echo -e "${red}Coincidental domains found between source and target!${noclr}"
 cat /root/preexisting.txt
 if yesNo "If you continue with the migration, data in these domains will be overwritten! Do you want to continue?"; then
  echo -e Continuing...
 else
  echo -e Exiting...
  exit 0
 fi
else
 echo -e "${green}No coincidental domains found.${noclr}"
fi
}

createbackup() { #verbosely (-v) make a configuration-only (-c) backup on the source server ($tmpfolder/backup.tar)
test -e $tmpfolder/backup.tar && mv $tmpfolder/backup.tar{,.`date +%F.%T`.bak}
echo -e "${purple}Generating full backup to $tmpfolder/backup.tar...${noclr}"
if [[ `cat /usr/local/psa/version | awk '{print $1}' | cut -c1` -eq 8 ]]; then
 echo -e "Plesk 8 detected!"
 /usr/local/psa/bin/pleskbackup -cvz all $tmpfolder/backup.tar
else
 /usr/local/psa/bin/pleskbackup server -v -c --skip-logs --output-file=$tmpfolder/backup.tar
fi
}

syncbackup() { #copy the backup to the target server
echo -e "${purple}Copying backup to the target server...${noclr}"
ssh -q $target -p$port "test -e $tmpfolder/backup.tar && mv $tmpfolder/backup.tar{,.`date +%F.%T`.bak}"
rsync -avHPe "ssh -q -p$port" $tmpfolder/backup.tar $target:$tmpfolder/
}

ipmaptool () { #this will set the ip mapping to $target server ips
echo -e "${purple}Setting IP mapping on target server...${noclr}"
ssh -q $target -p$port "test -e $tmpfolder/mapfile.txt && mv $tmpfolder/mapfile.txt{,.`date +%F.%T`.bak}"
ssh -q $target -p$port "/usr/local/psa/bin/pleskrestore --create-map $tmpfolder/backup.tar -map $tmpfolder/mapfile.txt"
echo -e "${white}Target machine mapped addresses as follows:${noclr}"
ssh -q $target -p$port "cat $tmpfolder/mapfile.txt" | grep '\->'
if yesNo "Does this look alright to you?"; then
 echo -e "${white}Moving on... everything should be hands-off until the sync is complete.${noclr}"
 sleep 3
else
 echo -e "${red}Go ahead and edit the map file ($tmpfolder/mapfile.txt) on the target server now. I'll wait...${noclr}"
 read
 echo -e "${white}Continuing... everything should be hands-off until the sync is complete.${noclr}"
 sleep 3
fi
}

restore() { #The actual restoration function. will restore the configuration backup at a server level, to include all resellers, clients and domains.
echo -e "${purple}Restoring configuration file...
This part may not be completely verbose...${noclr}"
numdomains=`mysql -u admin -p$(cat /etc/psa/.psa.shadow) -Ns psa -e "select name from domains;" | wc -l`
targetmysqlpass=`ssh -q $target "cat /etc/psa/.psa.shadow"`
#ssh -q $target -p$port "test -f /root/.my.cnf && cp -a /root/.my.cnf{,.migrationbak}"
#ssh -q $target -p$port "echo '[client]
#user=admin
#pass=$targetmysqlpass' >> /root/.my.cnf" # this will get passwordless mysql logins temporarily, only way to check the database on the remote server.
#restoreprogress &
#MYSELF=$!
ssh -q $target -p$port "/usr/local/psa/bin/pleskrestore --restore $tmpfolder/backup.tar -level server -map $tmpfolder/mapfile.txt -verbose"
#kill $MYSELF &> /dev/null
echo -e "${green}
Restore completed! ${purple}Testing restored domain list...${noclr}"
targetnumdomains=`ssh -q $target -p$port "mysql -u admin -p$targetmysqlpass -Ns psa -e 'select name from domains;'" | wc -l`
#ssh -q $target -p$port "test -f /root/.my.cnf.migrationbak && mv -f /root/.my.cnf{.migrationbak,}"
echo -e "
${white}There are $numdomains domains on the source server and $targetnumdomains domains on the target server.${noclr}"
#if yesNo "Does this make sense to you?"; then
 echo -e Carrying on!
 databasefinalsync
 rsynchomedirs
 rsyncemail
# else
# echo Problem right here... exiting!
# sleep 1
# exit
#fi
}

restoreprogress() { #show the progress of the restore in terms of number of domains restored
while true; do
 numrestored=`ssh -q $target -p$port "mysql psa -u admin -p$targetmysqlpass -Ns -e 'select name from domains' | wc -l"`
 echo -ne "${white}Restored ${noclr}$numrestored/$numdomains...\r"
 sleep 6
done
}

#================
#end regular sync
#=================
#start client sync
#=================

clientcheck() { #Check the $clientlistfile against subscriptions on the source server
clientlist=`mysql psa -u admin -p$(cat /etc/psa/.psa.shadow) -Ns -e 'SELECT c.login, d.name FROM clients AS c JOIN domains AS d ON d.cl_id = c.id;'`
echo -e "${purple}Checking $clientlistfile for bad entries...${noclr}"
rm -f /var/clientcheckfail.txt
for client in `cat $clientlistfile`; do
 if [[ ! `echo $clientlist | grep $client` ]]; then
  echo $client > /var/clientcheckfail.txt
 fi
done
if [[ -f /var/clientcheckfail.txt ]]; then
 echo -e "${red}Found non-client entries in $clientlistfile:${noclr}
"
 cat /var/clientcheckfail.txt
 echo -e "
${red}Please double check these lines and remove them if necessary.${noclr}"
 if yesNo "Override bad entries check? Script will fail for invalid users."; then
  echo -e "Moving on."
 else
  echo -e "Exiting"
  exit
 fi
else
 echo -e "${green}Looks good. Moving on.${noclr}"
fi
}

syncclients() { #make a backup per client and restore on the target machine
for client in `cat $clientlistfile`; do
 clientdomains=`mysql psa -u admin -p$(cat /etc/psa/.psa.shadow) -Ns -e 'SELECT c.login, d.name FROM clients AS c JOIN domains AS d ON d.cl_id = c.id;' | grep ^$client\s* | awk '{print $2}'`
 echo -e "${purple}Backing up ${white}$client${purple}...${noclr}"
 /usr/local/psa/bin/pleskbackup clients-name $client -c --skip-logs --output-file=$tmpfolder/backup.$client.tar
 if [[ -f $tmpfolder/backup.$client.tar ]]; then
  echo -e "${purple}Transferring $client and making mapfile...${noclr}"
  rsync -aHPe "ssh -q -p$port" $tmpfolder/backup.$client.tar root@$target:$tmpfolder/
  ssh -q -p$port root@$target "/usr/local/psa/bin/pleskrestore --create-map $tmpfolder/backup.$client.tar -map $tmpfolder/backup.$client.map"
  echo -e "${purple}Executing restore of $client (this can take a while, please be patient...)${noclr}"
  ssh -q -p$port root@$target "/usr/local/psa/bin/pleskrestore --restore $tmpfolder/backup.$client.tar -map $tmpfolder/backup.$client.map -level clients"
  restoredtest=`echo $clientdomains | awk '{print $1}'`
  restored=`ssh -q -p$port root@$target "\ls -A /var/www/vhosts/ | grep ^$restoredtest$"` #check to see if domain folder exists to test restore
  if [ $restored ]; then
   echo -e "${green}$client restored ok. ${purple}Syncing data...${noclr}"
   syncclidatabases
   syncclidocroot
   syncclimail
  else
   echo -e "${red}$client did not seem to restore correctly!${noclr}"
   echo $client >> $didnotrestore
  fi
 else
  echo -e "${red}Backup of $client failed. Does this client really exist?${noclr}"
  echo $client >> $didnotbackup
 fi
done
dbsyncscript
}

syncclidatabases() { # option A, lots of imports
echo -e "${purple}Determining databases for sync...${noclr}"
domdatabases=`mysql -u admin -p$(cat /etc/psa/.psa.shadow) -Ns psa -e "SELECT domains.name AS domain_name, data_bases.name AS database_name, clients.login FROM data_bases, clients, domains WHERE data_bases.dom_id = domains.id AND domains.cl_id = clients.id ORDER BY domain_name;" | grep \s+$client$ | awk '{print $2}' | sort | uniq`
for db in $domdatabases; do
 echo -e "Dumping $db for $client..."
 mysqldump -u admin -p$(cat /etc/psa/.psa.shadow) $db > $tmpfolder/dbdumps/$db.sql
done
echo -e "${green}Databases for $client complete.${noclr}"
rsync -avHPe "ssh -q -p$port" $tmpfolder/dbdumps root@$target:$tmpfolder/ --update
echo $domdatabases >> $tmpfolder/databaselist.txt
}

syncclidocroot() { #sync the docroots tied to a particular client
echo -e "${purple}Syncing docroots for $client...${noclr}"
for each in $clientdomains; do
 echo -e $each
 if [[ -d /var/www/vhosts/$each ]]; then
  rsync -avHPe "ssh -q -p$port" /var/www/vhosts/$each root@$target:/var/www/vhosts/ --exclude=conf >> $logfile 2>&1
  rsync -avHPe "ssh -q -p$port" /var/www/vhosts/$each/httpdocs root@$target:/var/www/vhosts/$each/ --update >> $logfile 2>&1
 fi
done
}

syncclimail() { #sync mail tied to a particular subscription
echo -e "${purple}Syncing mail for $client...${noclr}"
for each in $clientdomains; do
 echo -e $each
 if [[ -d /var/qmail/mailnames/$each ]]; then
  rsync -avHPe "ssh -q -p$port" /var/qmail/mailnames/$each root@$target:/var/qmail/mailnames/ >> $logfile 2>&1
 fi
done
}

#===============
#end client sync
#======================
#start domain list sync
#======================

subcheck() { #Check the $domlistfile against subscriptions on the source server
if [[ `cat /usr/local/psa/version | awk '{print $1}' | cut -c1` -eq 8 ]]; then
 echo -e "Plesk 8 detected! I hope you selected the right domains 'cause I can't check!"
 sleep 5
else
 sublist=`mysql psa -u admin -p$(cat /etc/psa/.psa.shadow) -Ns -e 'SELECT name FROM domains JOIN Subscriptions ON Subscriptions.object_id = domains.id;'`
 echo -e "${purple}Checking $domlistfile for bad entries...${noclr}"
 rm -f /var/subcheckfail.txt
 for domain in `cat $domlistfile`; do
  if [[ ! `echo $sublist | grep $domain` ]]; then
   echo $domain > /var/subcheckfail.txt
  fi
 done
 if [[ -f /var/subcheckfail.txt ]]; then
  echo -e "${red}Found non-subscription domains in $domlistfile:${noclr}
 "
  cat /var/subcheckfail.txt
  echo -e "
 ${red}Please double check these lines and remove them if necessary. If the source server is less than plesk 11, this might not work at all...${noclr}"
  if yesNo "Override bad entries check? Script will fail for invalid domains."; then
   echo -e "Moving on."
  else
   echo -e "Exiting"
   exit
  fi
 else
  echo -e "${green}Looks good. Moving on.${noclr}"
 fi
fi
}

syncdomains() { #make a backup per subscription and restore on the target machine
for domain in `cat $domlistfile`; do
 echo -e "${purple}Backing up ${white}$domain${purple}...${noclr}"
 /usr/local/psa/bin/pleskbackup domains-name $domain -c --skip-logs --output-file=$tmpfolder/backup.$domain.tar
 if [[ -f $tmpfolder/backup.$domain.tar ]]; then
  echo -e "${purple}Transferring $domain and making mapfile...${noclr}"
  rsync -aHPe "ssh -q -p$port" $tmpfolder/backup.$domain.tar root@$target:$tmpfolder/
  ssh -q -p$port root@$target "/usr/local/psa/bin/pleskrestore --create-map $tmpfolder/backup.$domain.tar -map $tmpfolder/backup.$domain.map"
  echo -e "${purple}Executing restore of $domain (this can take a while, please be patient...)${noclr}"
  ssh -q -p$port root@$target "/usr/local/psa/bin/pleskrestore --restore $tmpfolder/backup.$domain.tar -map $tmpfolder/backup.$domain.map -level domains"
  restored=`ssh -q -p$port root@$target "\ls -A /var/www/vhosts/ | grep ^$domain$"` #check to see if domain folder exists to test restore
  if [ $restored ]; then
   echo -e "${green}$domain restored ok. ${purple}Syncing data...${noclr}"
   syncdomdatabases
   determineowned
   syncdomdocroot
   syncdommail
  else
   echo -e "${red}$domain did not seem to restore correctly!${noclr}"
   echo $domain >> $didnotrestore
  fi
 else
  echo -e "${red}Backup of $domain failed. Is this domain a subscription?${noclr}"
  echo $domain >> $didnotbackup
 fi
done
dbsyncscript
}

syncdomdatabases() { # option A, lots of imports
echo -e "${purple}Determining databases for sync...${noclr}"
domdatabases=`mysql -u admin -p$(cat /etc/psa/.psa.shadow) -Ns psa -e "SELECT domains.name AS domain_name, data_bases.name AS database_name FROM data_bases, domains WHERE data_bases.dom_id = domains.id ORDER BY domain_name;" | grep $domain | awk '{print $2}' | sort | uniq`
for db in $domdatabases; do
 echo -e "Dumping $db for $domain..."
 mysqldump -u admin -p$(cat /etc/psa/.psa.shadow) $db > $tmpfolder/dbdumps/$db.sql
done
echo -e "${green}Databases for $domain complete.${noclr}"
rsync -avHPe "ssh -q -p$port" $tmpfolder/dbdumps root@$target:$tmpfolder/
echo $domdatabases >> $tmpfolder/databaselist.txt
###write dbrestore on target in screen which will close automatically
}

determineowned() { #determine which domains are owned by a subscription based on the backup file, depends on $domain being set
domainowned=`tar -Oxf $tmpfolder/backup.$domain.tar *.xml | grep www\= | tr [:space:] '\n' | grep name | cut -d\" -f2 | sort | uniq`
}

syncdomdocroot() { #sync the docroots tied to a particular subscription
echo -e "${purple}Syncing docroots for $domain...${noclr}"
for each in $domainowned; do
 echo $each
 if [[ -d /var/www/vhosts/$each ]]; then
  rsync -avHPe "ssh -q -p$port" /var/www/vhosts/$each root@$target:/var/www/vhosts/ --exclude=conf >> $logfile 2>&1
  rsync -avHPe "ssh -q -p$port" /var/www/vhosts/$each/httpdocs root@$target:/var/www/vhosts/$each/ --update >> $logfile 2>&1
 fi
done
}

syncdommail() { #sync mail tied to a particular subscription
echo -e "${purple}Syncing mail for $domain...${noclr}"
for each in $domainowned; do
 echo -e $each
 if [[ -d /var/qmail/mailnames/$each ]]; then
  rsync -avHPe "ssh -q -p$port" /var/qmail/mailnames/$each root@$target:/var/qmail/mailnames/ >> $logfile 2>&1
 fi
done
}

#====================
#end domain list sync
#====================
#start postsync
#==============

dnrcheck() { #Checks to see if there is anything in didnotrestore.txt and displays it here
if [ -f $didnotrestore ]; then
 echo -e "${red}Some domains may not have restored:${noclr}"
 cat $didnotrestore
 echo -e "${yellow}Enter to continue...${noclr}"
 read
fi
if [[ $didnotbackup && -f $didnotbackup ]]; then
 echo -e "${red}Some domains may not have backed up properly:${noclr}"
 cat $didnotbackup
 echo -e "${yellow}Enter to continue...${noclr}"
 read
fi
}

hostsfile() { #Generate a hosts file on the target machine
echo -e "${purple}Generating hosts file...${noclr}"
cat > /var/pleskhosts.sh <<'EOF'
#!/bin/bash
#awalilko@lw 09/06/12
hostsfile=/var/www/vhosts/default/htdocs/hostsfile.txt
althostsfile=/var/www/vhosts/default/htdocs/hosts.txt
ip=`/usr/local/psa/bin/ipmanage -l | grep " S " | head -n1 | cut -d\: -f2 | cut -d\/ -f1`
#backup hosts file if it exists
if [ -s $hostsfile ]; then
 mv $hostsfile{,.bak}
fi
if [ -s $althostsfile ]; then
 mv $althostsfile{,.bak}
fi
#create one line for each domain and subdomain
echo "Generating entries..."
for domain in `mysql psa -u admin -p$(cat /etc/psa/.psa.shadow) -Ns -e 'select name from domains' | sort | uniq`; do
  domip=`/usr/local/psa/bin/domain --info $domain | grep address | cut -d\: -f2 | sed -e 's/^[ \t]*//'`;
  echo $domip  $domain www.$domain >> $hostsfile;
done
echo "Done!"
#create one line per ip
echo "Generating alternate file..."
for domip in `cat $hostsfile | cut -d\  -f1 | sort | uniq | grep -v [a-zA-Z]`; do
  echo $domip `cat $hostsfile | grep $domip | cut -d\  -f2-3 | tr '\n' ' '` >> $althostsfile;
done
echo "Done!"
#correct server to accept requests by IP
echo "Correcting for ModSec..."
if [ -s /etc/httpd/modsecurity.d ]; then
  grep 960017 /etc/httpd/modsecurity.d/* -Rl | xargs sed -i '/960017/s/^/\#/g';
  service httpd restart;
  echo "ModSec corrected! All Set!"
else
  echo "ModSec not found! All set!"
fi
#output resulting file link
echo
cat $althostsfile
echo
echo "One line per IP at http://$ip/hosts.txt"
echo "One line per domain at http://$ip/hostsfile.txt"
echo
EOF
rsync -aHPe "ssh -q -p$port" /var/pleskhosts.sh $target:/var/
ssh -q $target -p$port "bash /var/pleskhosts.sh"
sleep 2
}

removekey() { #removes the ssh key from the target server
if yesNo "Remove SSH key from target server?"; then
echo -e "Removing ssh key from remote server..."
 ssh -q -p$port $target "
 mv ~/.ssh/authorized_keys{,.initialsync.`date +%F`};
 if [ -f ~/.ssh/authorized_keys.syncbak ]; then
  cp -rp ~/.ssh/authorized_keys{.syncbak,};
 fi"
fi
}

# This is where the actual script is run. 
main

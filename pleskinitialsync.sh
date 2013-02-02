#!/bin/bash
#Plesk migration script
#by awalilko@liquidweb.com
#many thanks to abrevick@lw for his cpanel initialsync script, off of which this was based.
ver='beta 3.2 dec.18.12'
#=========================================================
#####changelog
#sept 07 2012 alpha version tested, roughly working
#sept 18 2012 altered createbackup() to make a backup of the backup before making a backup, dawg.
#sept 18 2012 added better comments
#sept 19 2012 commented out the ipremap tool call in ipcheck(). while a neat piece of work, it isnt needed yet.
#sept 19 2012 added check for existance of /var/www/vhosts/$domain on target machine before rsyncing, add domain to /var/didnotrestore.txt if it does not exist
#sept 21 2012 corrected spelling mistakes in variable names at ipcheck()
#sept 21 2012 wrote dns sync command for finalsync()
#sept 21 2012 tested full initial sync from start to finish. moved to beta 1
#sept 25 2012 added test for screen
#sept 29 2012 cleaned up homedirsync test for restoration and found a missed 'fi' comment. tested on a real migration, worked. moved to beta2
#oct 27 2012 added removal of ssh key from target server for all sync levels
#dec 05 2012 check for coincidental domains on target server and query for overwrite
#dec 18 2012 alternate pleskbackup command if on plesk 8
#=========================================================
#####to do
#determine if per-domain syncing is possible
#logging (there is none)
#plesk11 business model upgrade?

##presync
#ssl cert check for individual domains ?
#operable mysql password check on source and target to confirm that mysql is accessible on both
#=========================================================
test -f /var/didnotrestore.txt && mv /var/didnotrestore.txt{,.`date +%F.%T`.bak}

yesNo() { #generic yesNo function 
#repeat if yes or no option not valid
while true; do
#$* read every parameter giving to the yesNo function which will be the message
 echo -n "$* (Y/N)? "
 #junk holds the extra parameters yn holds the first parameters
 read yn junk
 case $yn in
  yes|Yes|YES|y|Y)
    return 0  ;;
  no|No|n|N|NO)
    return 1  ;;
  *)
    echo "Please enter y or n."
 esac
done
}

main() {
mainloop=0
while [ $mainloop == 0 ]; do
 clear
 echo "Welcome to the Plesk Migration Tool!"
 echo "Version: $ver"
 if [[ ! "${STY}" ]]; then
  echo "
You are not in a screen session. Please run this script in a screen session!"
 fi
 echo "
Select your migration type:
 1) Full initial sync (all plesk accounts and all data)
 2) Update sync (homedirs, databases, and mail files only)
 3) Final sync
 4) Quit
"
 echo Enter your choice:
 read choice
 case $choice in
  1)
   initialsync
   mainloop=1;;
  2)
   updatesync
   mainloop=1;;
  3) 
   finalsync
   mainloop=1;;
  4)
   echo "Quitting, quitter!"
   exit 0;;
  *)
   echo Please select a valid migration type.
   sleep 2
   clear
 esac
done
echo Finished!
exit 
}

initialsync() {
echo Starting full initial sync.
presync
createbackup
syncbackup
ipmaptool
restore
dnrcheck
hostsfile
removekey
}

presync() {
echo Starting pre-backup tasks.
dnscheck
rsyncupgrade
lowerttls
getip
licensecheck
ipcheck
phpupgrade
autoinstaller
}

updatesync() {
echo Starting update sync.
rsyncupgrade
getip
databasefinalsync
rsynchomedirs
rsyncemail
removekey
}

finalsync() {
echo Starting final sync.

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

echo Press enter to begin the final sync!
read

rsyncupgrade

#stop services
if [ $stopservices ]; then
 echo "Stopping Services..."
 /etc/init.d/httpd stop
 /etc/init.d/qmail stop
 /etc/init.d/exim stop
else
 echo "Not stopping services..."
fi

#do the sync
databasefinalsync
finalrsynchomedirs
rsyncemail

#copy the dns info back
if [ $copydns ]; then
 echo "Copying zone file information over from new server..."
 if [ `ssh $target -p$port "ls /var/ | grep ^mapfile.txt$"` ]; then
  rsync -avHPe "ssh -p$port" $target:/var/mapfile.txt /var/
  cat /var/mapfile.txt | grep "\->" | awk '{print "mysql psa -u admin -p$(cat /etc/psa/.psa.shadow) -D psa -e \"UPDATE dns_recs SET val=\\\""$1"\\\", displayVal=\\\""$1"\\\" WHERE val=\\\""$4"\\\"\""}' | sh
  mysql psa -u admin -p$(cat /etc/psa/.psa.shadow) -Ns -e 'SELECT name FROM domains' | awk '{print "/usr/local/psa/admin/sbin/dnsmng update " $1 }' | sh
 else
  echo "The IP mapping file (/var/mapfile.txt)  was not found on the target server! please update the DNS records on your own!"
  sleep 3
  mapfilefail=1
 fi
fi

#restart services
if [ $restartservices ]; then
 echo "Restarting services..."
 /etc/init.d/httpd start
 /etc/init.d/qmail start
 /etc/init.d/exim start
else
 echo "Skipping restart of services..."
fi

#display mysqldump errors
if [ -s /tmp/mysqldump.log ]; then
 echo 
 echo 'Errors detected during mysqldumps:'
 cat /tmp/mysqldump.log
 echo "End of errors from /tmp/mysqldump.log."
 sleep 1
fi

echo 'Final sync complete, check the screen "dbsync" on the remote server to ensure all databases imported correctly.'
if [ $mapfilefail ]; then
 echo "The mapfile on the target server could not be found! Please remember to update DNS!"
fi
removekey
}

databasefinalsync() { #perform just a database sync, reimporting on the target side.
echo "Dumping the databases..."
test -d /var/dbdumps && mv /var/dbdumps{,.`date +%F.%T`.bak}
mkdir -p /var/dbdumps
ssh $target -p$port 'test -d /var/dbdumps && mv /var/dbdumps{,.`date +%F.%T`.bak}'
mysqldumpver=`mysqldump --version |cut -d" " -f6 |cut -d, -f1`
for db in `mysql -u admin -p$(cat /etc/psa/.psa.shadow) -Ns -e "show databases" | egrep -v "^(psa|mysql|horde|information_schema|phpmyadmin.*)$"`; do
 mysqldumpfunction
done

#move the dumps to the new server
rsync -avHlPze "ssh -p$port" /var/dbdumps $target:/var/

#start import of databases in screen on target
dbsyncscript
}

mysqldumpfunction() { #argument is 'db' provided by a loop
echo "Dumping $db"
if [[ $mysqldumpver < 5.0.42 ]]; then
 mysqldump -u admin -p$(cat /etc/psa/.psa.shadow) --add-drop-table $db > /var/dbdumps/$db.sql
else
 mysqldump -u admin -p$(cat /etc/psa/.psa.shadow) --force --add-drop-table --log-error=/tmp/mysqldump.log $db > /var/dbdumps/$db.sql
fi
}

dbsyncscript () { #create a script to restore the databases on the target server, then run it there in a screen
cat > /var/dbsync.sh <<'EOF'
#!/bin/bash
#ran on remote server to sync dbs.
LOG=/var/dbdumps/dbdumps.log
if [ -d /var/dbdumps ]; then
 cd /var/dbdumps
 echo "Dump dated `date`" > $LOG
 #if the prefinalsyncdb directory exists, rename it
 test -d /var/prefinalsyncdbs && mv /var/prefinalsyncdbs{,.`date +%F.%R`.bak}
 mkdir /var/prefinalsyncdbs
 for each in `ls|grep .sql|cut -d '.' -f1`; do
  echo "dumping $each" |tee -a $LOG
  (mysqldump $each > /var/prefinalsyncdbs/$each.sql) 2>>$LOG
  echo " importing $each" | tee -a $LOG
  (mysql $each < /var/dbdumps/$each.sql)  2>>$LOG
 done
 echo "Finished, hit a key to see the log."
 read
 less $LOG
else
 echo "/var/dbdumps not found"
 read
fi
EOF
rsync -aHPe "ssh -p$port" /var/dbsync.sh $target:/var/
ssh $target -p$port "screen -S dbsync -d -m bash /var/dbsync.sh" &
echo Databases are importing in a screen on the target server. Be sure to check there to make sure they all imported OK.
sleep 2
}

rsynchomedirs() { #sync the docroots of all users, exluding the conf folder. the conf folder holds ip-specific data, which we do not want to migrate.
for each in `mysql -u admin -p$(cat /etc/psa/.psa.shadow) -Ns psa -e "select name from domains;"`; do
 if [ `ssh $target -p$port "ls /var/www/vhosts/ | grep ^$each$"` ]; then
  rsync -avHPe 'ssh -p$port' /var/www/vhosts/$each root@$target:/var/www/vhosts/ --exclude=conf
 else
  echo "$each did not restore remotely"
  echo $each >> /var/didnotrestore.txt
fi
done
}

finalrsynchomedirs() { #as with rsynchomedirs(), but without remote home check.
for each in `mysql -u admin -p$(cat /etc/psa/.psa.shadow) -Ns psa -e "select name from domains;"`; do
 rsync -avHPe "ssh -p$port" /var/ww/vhosts/$each root@$target:/var/www/vhosts/ --update --exclude=conf
done
}

rsyncemail() { #rsync the whole mail folder
echo Syncing email...
rsync -avHPe "ssh -p$port" /var/qmail/mailnames/ root@$target:/var/qmail/mailnames/ --update
}

dnscheck() { #check the current DNS settings based on the defined domain list
echo "Checking Current dns..."
if [ -f /root/dns.txt ]; then
 echo "Found /root/dns.txt"
 sleep 3
 cat /root/dns.txt | sort -n +3 -2 | more
else
 domainlist=`mysql psa -u admin -p$(cat /etc/psa/.psa.shadow) -Ns -e 'select name from domains'`
 for each in $domainlist; do echo $each\ `dig @8.8.8.8 NS +short $each |sed 's/\.$//g'`\ `dig @8.8.8.8 +short $each` ; done | grep -v \ \ | column -t > /root/dns.txt
 cat /root/dns.txt | sort -n +3 -2 | more
fi
echo "Enter to continue..."
read
}

rsyncupgrade () { #upgrade rsync to v3.0 if not already there
RSYNCVERSION=`rsync --version |head -n1 |awk '{print $3}'`
rsyncmajor=`echo $RSYNCVERSION |cut -d. -f1`
if [[ $rsyncmajor -lt 3 ]]; then
 echo "Updating rsync..."
 LOCALCENT=`cat /etc/redhat-release |awk '{print $3}'|cut -d '.' -f1`
 LOCALARCH=`uname -i`
 if [[ $LOCALCENT -eq 6 ]]; then
  rpm -Uvh http://migration.sysres.liquidweb.com//rsync/rsync-3.0.9-1.el6.rfx.$LOCALARCH.rpm
 else
  rpm -Uvh http://migration.sysres.liquidweb.com//rsync/rsync-3.0.0-1.el$LOCALCENT.rf.$LOCALARCH.rpm
 fi
else
 echo "Rsync already up to date."
fi
}

lowerttls() { #lower the TTLs of the DNS records in the psa database, and reload each domain through dnsmng
echo Lowering TTL values on local server...
mysql psa -u admin -p$(cat /etc/psa/.psa.shadow) -e "insert into misc values ('soa_TTL','300');"
mysql psa -u admin -p$(cat /etc/psa/.psa.shadow) -e "update psa.dns_zone set ttl_unit=1, ttl=300;"
mysql psa -u admin -p$(cat /etc/psa/.psa.shadow) -Ns -e 'select name from domains' | awk '{print "/usr/local/psa/admin/sbin/dnsmng --update " $1 }' | sh
}

getip() { #determine if the target server variable exists from a previous migration
echo "Getting Ip for destination server..."
#check for previous migration
ipfile=/root/dest.ip.txt
if [ -f $ipfile ]; then
 target=`cat $ipfile`
 echo "Ip from previous migration found: $target"
 getport
 if yesNo "Is $target the server you want?  Otherwise enter No to input new ip." ; then
  echo "Ok, continuing with $target"
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
echo
echo -n 'Enter destination server IP: ';
read target
echo $target > $ipfile
getport
sshkeygen
}

getport() { #get the target server ssh port
echo "Getting ssh port..."
if [ -s /root/dest.port.txt ]; then
 port=`cat /root/dest.port.txt`
 echo "Previous Ssh port found: $port"
else
 echo -n "Enter destination server SSH port [default 22]: "
 read port
fi
if [ -z $port ]; then
 echo "No port given, assuming 22"
 port=22
fi
echo $port > /root/dest.port.txt
}

sshkeygen() { #quietly create an ssh key if it does not exist and copy it to the remote server
echo "Generating SSH keys..."
if ! [ -f ~/.ssh/id_rsa ]; then
 ssh-keygen -q -N "" -t rsa -f ~/.ssh/id_rsa
fi
echo "Copying key to remote server..."
cat ~/.ssh/id_rsa.pub | ssh $target -p$port "cp -rp ~/.ssh/authorized_keys{,.syncbak} ; mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys"
ssh $target -p$port "echo \'Connected!\';  cat /etc/hosts| grep $target "
}

licensecheck() { #check the license of the target server to make sure it has enough domains in it
echo Checking the target for a sufficiently permissive license key...
numdomains=`mysql -u admin -p$(cat /etc/psa/.psa.shadow) -Ns psa -e "select name from domains;" | wc -l`
targetlimdom=`ssh $target -p$port "/usr/local/psa/bin/keyinfo --list | grep lim_dom\:" | awk '{print $2}'`
echo "Source server has $numdomains domains, target license permits $targetlimdom domains." | sed -e 's/\-1/unlimited/g'
if [[ $targetlimdom -eq -1 ]]; then
 echo "Target license allows for unlimited domains, and can hold all these limes!"
elif [[ $numdomains -le $targetlimdom ]]; then
 echo "Target license seems to have a large enough key to hold all these limes."
else
 echo "Target server probably cannot hold all these limes! Please update target server license key!"
fi
if yesNo "Continue with migration?"; then
 echo Do want...
else
 echo Do not want...
 exit 0
fi
}

domainexistcheck() { #make sure that domains that exist on the source do not already have a folder on the target
echo "Checking for coincidental domains on target server..."
catpreexisting=0
for each in `mysql -u admin -p$(cat /etc/psa/.psa.shadow) -Ns psa -e "select name from domains;"`; do
 if [ `ssh $target -p$port "ls /var/www/vhosts/ | grep ^$each$"` ]; then
  echo $each >> /root/preexisting.txt
  catpreexisting=1
 fi
done
if [[ $catpreexisting -eq 1 ]]; then
 echo "Coincidental domains found between source and target!"
 cat /root/preexisting.txt
 if yesno "If you continue with the migration, data in these domains will be overwritten! Do you want to continue?"; then
  echo Continuing...
 else
  echo Exiting...
  exit 0
 fi
else
 echo "No coincidental domains found."
fi
}

ipcheck() { #check to ensure that there are the necessary number of IPs on the target machine
echo Checking for a sufficient number of IPs...
shared=`/usr/local/psa/bin/ipmanage --ip_list | grep " S " | wc -l`
exclusive=`/usr/local/psa/bin/ipmanage --ip_list | grep " E " | wc -l`
targetshared=`ssh $target -p$port "/usr/local/psa/bin/ipmanage --ip_list | grep ' S ' | wc -l"`
targetexclusive=`ssh $target -p$port "/usr/local/psa/bin/ipmanage --ip_list | grep ' E ' | wc -l"`

#compare the number of ips on the source and the target machines
echo "
On the source machine, there are $shared shared IPs and $exclusive exclusive IPs available."
if [[ $targetshared -ge $shared && $targetexclusive -ge $exclusive ]]; then
 echo "There are also $targetshared shared IPs on the target machine, and $targetexclusive exclusive IPs. This seems like it will work."
else
 echo "But, there are only $targetshared shared IPs and $targetexclusive exclusive IPs on the target machine. That doesn't seem like it will work."
fi
if yesNo "Do these numbers seem ok to you? Yes to continue, no to exit and recheck things before proceeding."; then
 echo Proceeding with migration.
 ###commented out ipremap() as the default plesk mapping tool seems to work well on its own
 #ipremap
else
 echo Exiting.
 exit 0
fi
}

ipremap() { #create a potential mapping file array
#place the ips into a standard array based on the number of source IPs
echo "Matching IPs for map tool..."
x=0
while [ $shared -gt $x ]; do
 sharedip[$x]=`/usr/local/psa/bin/ipmanage --ip_list | grep " S " | awk NR==$(( $x + 1 )) | cut -d: -f2 | cut -d\/ -f1`
 targetsharedip[$x]=`ssh $target -p$port "/usr/local/psa/bin/ipmanage --ip_list | grep ' S '" | awk NR==$(( $x + 1 )) | cut -d: -f2 | cut -d\/ -f1`
 x=$(( $x + 1 ))
done
y=0
while [ $exclusive -gt $y ]; do
 exclusiveip[$x]=`/usr/local/psa/bin/ipmanage --ip_list | grep " E " | awk NR==$(( $y + 1 )) | cut -d: -f2 | cut -d\/ -f1`
 targetexclusiveip[$x]=`ssh $target -p$port "/usr/local/psa/bin/ipmanage --ip_list | grep ' E '" | awk NR==$(( $y + 1 )) | cut -d: -f2 | cut -d\/ -f1`
 y=$(( $y + 1 ))
done

#confirm that the mapping is ok
echo "Please confirm this mapping:
"
echo Shared IPs:
x=0
while [ ${#sharedip[@]} -gt $x ]; do
 echo "${sharedip[$x]} :: ${targetsharedip[$x]}"
 x=$(( $x + 1 ))
done
echo "
Exclusive IPs:"
y=0
while [ ${#exclusiveip[@]} -gt $y ]; do
 echo "${exclusiveip[$y]} :: ${targetexclusiveip[$y]}"
 y=$(( $y + 1 ))
done
echo ""
if yesNo "Does this seem to make sense?"; then
 echo Proceeding!
else
 echo Do not want. You will have to fix something here.
 exit 0
fi
}

autoinstaller() { #get plesk version on target machine and install pmm
echo Installing PMM and other utilities...
targetvernum=`ssh $target -p$port "cat /usr/local/psa/version" | awk '{print $1}' | sed 's/\./\_/g'`
ssh $target -p$port "/usr/local/psa/admin/bin/autoinstaller --select-release-id PLESK_$targetvernum --install-component pmm --install-component horde --install-component mailman --install-component backup"
}

phpupgrade() { #check for php 5.2.x and downgrade target if necessary.
echo Checking for PHP 5.2.x...
phpvernum=`php -v | head -n1 | awk '{print $2}'`
tgphpvernum=`ssh $target -p$port "php -v" | head -n1 | awk '{print $2}'`
if [[ `echo $phpvernum | awk -F. '{print $1}'` -eq 5 && `echo $phpvernum | awk -F. '{print $2}'` -eq 2 ]]; then
 echo "PHP 5.2.x detected! Current version on source server is $phpvernum."
 echo "Current version on target server is $tgphpvernum."
 if yesNo "Downgrade php on target server?"; then
  echo "Downgrading php to 5.2.17 on target..."
  ssh $target -p$port "rpm -qa | grep atomic |xargs rpm -e ; wget -q -O - http://www.atomicorp.com/installers/atomic.sh | sh "
  targetcent=`ssh $target -p$port "cat /etc/redhat-release" | awk '{print $3}' | cut -d. -f1`
  if [ $targetcent == 6 ]; then
   ssh $target -p$port "yum -y downgrade php-5.2.17-1.el6.art.x86_64 php-cli-5.2.17-1.el6.art php-common-5.2.17-1.el6.art php-devel-5.2.17-1.el6.art php-gd-5.2.17-1.el6.art php-imap-5.2.17-1.el6.art php-ncurses-5.2.17-1.el6.art php-mcrypt-5.2.17-1.el6.art php-mbstring-5.2.17-1.el6.art php-mysql-5.2.17-1.el6.art php-pdo-5.2.17-1.el6.art php-xml-5.2.17-1.el6.art php-pear php-snmp-5.2.17-1.el6.art php-xmlrpc-5.2.17-1.el6.art; /etc/init.d/httpd restart"
  elif [ $targetcent == 5 ]; then
   ssh $target -p$port "yum -y install php-5.2.17-1.el5.art.x86_64 php-common-5.2.17-1.el5.art php-gd-5.2.17-1.el5.art php-imap-5.2.17-1.el5.art php-mbstring-5.2.17-1.el5.art php-mysql-5.2.17-1.el5.art php-pdo-5.2.17-1.el5.art php-xml-5.2.17-1.el5.art; /etc/init.d/httpd restart"
  else
   echo Could not determine target OS version! Update this script or use a real OS!
  fi
  echo Target server is now using PHP `ssh $target -p$port "php -v" | head -n1 | awk '{print $2}'`.
 else
  echo Keeping target version at $tgphpvernum.
 fi
else
 echo PHP 5.2.x not detected.
fi
}

createbackup() { #verbosely (-v) make a configuration-only (-c) backup on the source server (/var/backup.tar)
test -e /var/backup.tar && mv /var/backup.tar{,.`date +%F.%T`.bak}
echo "Generating backup to /var/backup.tar..."
if [[ `cat /usr/local/psa/version | awk '{print $1}' | cut -c1` -eq 8 ]]; then
 echo "Plesk 8 detected!"
 /usr/local/psa/bin/pleskbackup -cvz all /var/backup.tar
else
 /usr/local/psa/bin/pleskbackup server -v -c --skip-logs --output-file=/var/backup.tar
fi
}

syncbackup() { #copy the backup to the target server
echo "Copying backup to the target server..."
ssh $target -p$port "test -e /var/backup.tar && mv /var/backup.tar{,.`date +%F.%T`.bak}"
rsync -avHPe "ssh -p$port" /var/backup.tar $target:/var/
}

ipmaptool () { #this will set the ip mapping as was decided in ipremap()
echo Setting IP mapping on target server...
ssh $target -p$port "test -e /var/mapfile.txt && mv /var/mapfile.txt{,.`date +%F.%T`.bak}"
ssh $target -p$port "/usr/local/psa/bin/pleskrestore --create-map /var/backup.tar -map /var/mapfile.txt"
echo "Target machine mapped addresses as follows:"
ssh $target -p$port "cat /var/mapfile.txt" | grep '\->'
if yesNo "Does this look alright to you?"; then
 echo Moving on...
else
# x=0
# while [ ${#sharedip[@]} -gt $x ]; do
#  ssh $target -p$port "sed -i 's/'${sharedip[$x]}'/'${targetsharedip[$x]}'/g' /var/mapfile.txt"
#  x=$(( $x + 1 ))
# done
# y=0
# while [ ${#exclusiveip[@]} -gt $y ]; do
#  ssh $target -p$port "sed -i 's/'${exclusiveip[$x]}'/'${targetexclusiveip[$x]}'/g' /var/mapfile.txt"
#  y=$(( $y + 1 ))
# done
 echo "Go ahead and edit the map file (/var/mapfile.txt) on the target server now. I'll wait..."
 read
 echo Continuing...
 sleep 4
fi
}

restore() { #The actual restoration function. will restore the configuration backup at a server level, to include all resellers, clients and domains.
echo "Restoring configuration file...
This part may not be verbose..."
ssh $target -p$port "/usr/local/psa/bin/pleskrestore --restore /var/backup.tar -level server -map /var/mapfile.txt -verbose"
echo "
Restore completed! Testing restored domain list..."
numdomains=`mysql -u admin -p$(cat /etc/psa/.psa.shadow) -Ns psa -e "select name from domains;" | wc -l`
targetmysqlpass=`ssh $target "cat /etc/psa/.psa.shadow"`
ssh $target -p$port "test -f /root/.my.cnf && cp -a /root/.my.cnf{,.migrationbak}"
ssh $target -p$port "echo '[client]
user=admin
pass=$targetmysqlpass' >> /root/.my.cnf"
targetnumdomains=`ssh $target -p$port "mysql -Ns psa -e 'select name from domains;'" | wc -l`
ssh $target -p$port "test -f /root/.my.cnf.migrationbak && mv -f /root/.my.cnf{.migrationbak,}"
echo "
There are $numdomains domains on the source server and $targetnumdomains domains on the target server."
#if yesNo "Does this make sense to you?"; then
 echo Carrying on!
 databasefinalsync
 rsynchomedirs
 rsyncemail
# else
# echo Problem right here... exiting!
# sleep 1
# exit
#fi
}

dnrcheck() { #Checks to see if there is anything in didnotrestore.txt and displays it here
if [ -f /var/didnotrestore.txt ]; then
 echo "Some domains may not have restored:"
 cat /var/didnotrestore.txt
 echo "Enter to continue..."
 read
fi
}

hostsfile() { #Generate a hosts file on the target machine
echo "Generating hosts file..."
cat > /var/pleskhosts.sh <<'EOF'
#!/bin/bash
#awalilko@lw 09/06/12
hostsfile=/var/www/vhosts/default/htdocs/hostsfile.txt
althostsfile=/var/www/vhosts/default/htdocs/hosts.txt
ip=`/usr/local/psa/bin/ipmanage --ip_list | grep " S " | head -n1 | cut -d\: -f2 | cut -d\/ -f1`
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
rsync -aHPe "ssh -p$port" /var/pleskhosts.sh $target:/var/
ssh $target -p$port "bash /var/pleskhosts.sh"
sleep 2
}

removekey() { #removes the ssh key from the target server
if yesNo "Remove SSH key from target server?"; then
echo "Removing ssh key from remote server..."
 ssh -p$port $target "
 mv ~/.ssh/authorized_keys{,.initialsync.`date +%F`};
 if [ -f ~/.ssh/authorized_keys.syncbak ]; then
  cp -rp ~/.ssh/authorized_keys{.syncbak,};
 fi"
fi
}

# This is where the actual script is run. 
main

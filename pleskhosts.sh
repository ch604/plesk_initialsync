#!/bin/bash
#awalilko@lw 01/15/13
#obtain hosts file entries from a plesk server

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

#determine if there is a hostname account and copy the files to that docroot
if [ -d /var/www/vhosts/$(hostname) ]; then
  cp $hostsfile /var/www/vhosts/$(hostname)/httpdocs/
  cp $althostsfile /var/www/vhosts/$(hostname)/httpdocs/
fi

#output resulting file link and a copyable block of hosts entries
echo 
cat $althostsfile
echo "
One line per IP at http://$ip/hosts.txt
One line per domain at http://$ip/hostsfile.txt
"

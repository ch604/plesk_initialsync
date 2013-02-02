#!/bin/bash
#ssullivan@lw, awalilko@lw 10/10/12
datadumpdir='/var/dbdumps/'
date=$(/bin/date +%HHours%m-%d-%Y)
mkdir -p $datadumpdir$date
echo "Creating MySQL dumps in $datadumpdir$date .."
for i in `mysql -u admin -p$(cat /etc/psa/.psa.shadow) -Ns -e "show databases" | egrep -v "^(psa|mysql|horde|information_schema|phpmyadmin.*)"`; do
   mysqldump --opt $i > $datadumpdir$date/$i.sql;
	echo "Created: $i.sql"
done
echo "Backups created in $datadumpdir$date"

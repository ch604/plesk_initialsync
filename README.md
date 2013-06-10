plesk_initialsync
=================

Migration and sync script for plesk to plesk migrations, written in bash. Sync adapts for versions of plesk from 8 through 11, but works best with the latest version of plesk as the target (11). Ability to migrate the full server, migrate by domain, or migrate by subscription/client. 

changelog:

sept 07 2012 alpha version tested, roughly working

sept 18 2012 altered createbackup() to make a backup of the backup before making a backup, dawg.

sept 18 2012 added better comments

sept 19 2012 commented out the ipremap tool call in ipcheck(). while a neat piece of work, it isnt needed yet.

sept 19 2012 added check for existance of /var/www/vhosts/$domain on target machine before rsyncing, add domain to /var/didnotrestore.txt if it does not exist

sept 21 2012 corrected spelling mistakes in variable names at ipcheck()

sept 21 2012 wrote dns sync command for finalsync()

sept 21 2012 tested full initial sync from start to finish. moved to beta 1

sept 25 2012 added test for screen

sept 29 2012 cleaned up homedirsync test for restoration and found a missed 'fi' comment. tested on a real migration, worked. moved to beta2

oct 27 2012 added removal of ssh key from target server for all sync levels

dec 05 2012 check for coincidental domains on target server and query for overwrite

dec 18 2012 alternate pleskbackup command if on plesk 8

feb 20 2013 install pmm/backup on local machine as well as target

feb 20 2013 install bind-utils if it is not already there

apr 02 2013 changed some single quotes to double quotes

apr 05 2013 PRELIMINARY PER DOMAIN BACKUPS, color for yesNo, subscription list generator

apr 09 2013 added the rest of the domain list sync scripts

apr 10 2013 cleaned up a bit, wrote restore() progress indicator. added DNS rewrite tasks to final sync. changed the restore function a bit to use the variable directly rather than add passwordless mysql logins.

apr 17 2013 added per client backups to per domain backups, fixed some syntax errors in the final sync (ww -> www)

apr 18 2013 updated rsync functions so that conf files under httpdocs are synced in an additional sync task. added some more color. added -q to ssh.

apr 19 2013 finalized coloration

may 03 2013 better plesk 8 compatibility

june 10 2013 silenced rsync outputs, fixed dbsync.sh to use password

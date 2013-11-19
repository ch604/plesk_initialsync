Plesk Initial Sync
==================

Migration and sync script for plesk to plesk migrations, written in bash. Sync adapts for versions of plesk from 8 through 11.x, but works best with the latest version of plesk as the target (11.5). Ability to migrate the full server, migrate by domain, or migrate by client (recommended method). 

Requirements
------------
Source server requires RHEL 4+ or equivalent with Plesk 8 or greater (may work with earlier versions, wild test subjects are hard to find), and mysql for database storage.

Target server requires RHEL 4+ (preferably 6) or equivalent with Plesk 10 or greater (shouldn't be migrating to anything earlier than this anyway) and mysql for database storage. Will require passworded root SSH login on any port, and screen to be installed. The system will also access specific remote servers in order to download specific RPMs for rsync. These calls can be bypassed or replaced with other external versions if you wish.

The servers should have increasing versions of Plesk. That is, the target server's Plesk version should be greater than or equal to the source's version. Migrating from 11.5 to 11.0, for instance, will fail.

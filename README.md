Plesk Initial Sync
==================

Migration and sync script for plesk to plesk migrations, written in bash. Sync adapts for versions of plesk from 8 through 11, but works best with the latest version of plesk as the target (11). Ability to migrate the full server, migrate by domain, or migrate by subscription/client (recommended method). 

Requirements
------------
Source server requires RHEL 4+ or equivalent with Plesk 8 or greater (may work with earlier versions, wild test subjects are hard to find), and mysql for database storage.

Target server requires RHEL 4+ (preferably 6) or equivalent with Plesk 10 or greater (shouldn't be migrating to anything earlier than this anyway) and mysql for database storage. Will require passworded root SSH login on any port and screen. The system will also access specific remote servers in order to download specific RPMs for rsync. These calls can be bypassed or replaced with other external versions if you wish.

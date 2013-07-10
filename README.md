Plesk Initial Sync
==================

Migration and sync script for plesk to plesk migrations, written in bash. Sync adapts for versions of plesk from 8 through 11, but works best with the latest version of plesk as the target (11). Ability to migrate the full server, migrate by domain, or migrate by subscription/client. 

Requirements
------------
Source server requires RHEL or equivalent with Plesk 8 or greater (may work with earlier versions), and mysql for database storage.

Target server requires RHEL or equivalent with Plesk 10 or greater (shouldn't be migrating to anything earlier than this anyway) and mysql for database storage. Will also require passworded root SSH login and screen.

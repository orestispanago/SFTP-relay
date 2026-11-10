## SFTP-relay

Receives files from a partner over SFTP and moves them to an FTP server, for FTP servers that can't offer SFTP accounts themselves.

* The partner logs in with a password to an SFTP-only account, with no shell, locked in its own folder (chroot)
* `relay.sh` (cron) uploads the files to FTP, keeping subfolders, and deletes them locally after a successful upload
* Files and folders changed in the last 5 min are skipped, as they may still be uploading
* Partial uploads (`*.part`, renamed by the client when complete) are skipped, and deleted after a day
* If the FTP server is down, files wait locally until a later run
* `relay.sh` logs to `logs/relay.log` and rotates it at 1 MB, keeping one old file

## SFTP account

Run as the user that will run the relay cron job (e.g. `pi`). Set the SFTP account name first:

```bash
SFTP_USER=partner
```

### 1. Account and folders

```bash
sudo useradd -m -d /srv/sftp/$SFTP_USER -s /usr/sbin/nologin $SFTP_USER
sudo passwd $SFTP_USER
sudo chown root:root /srv/sftp/$SFTP_USER
sudo chmod 755 /srv/sftp/$SFTP_USER
sudo mkdir /srv/sftp/$SFTP_USER/upload
sudo chown $SFTP_USER:$SFTP_USER /srv/sftp/$SFTP_USER/upload
sudo chmod 2775 /srv/sftp/$SFTP_USER/upload
sudo usermod -aG $SFTP_USER $USER
```

* The chroot folder must be owned by root. The account writes only in `upload/`.
* `2775` (setgid): new files and folders in `upload/` belong to the account's group. With the `-u 0002` umask in `sshd_relay.conf` they are group-writable, so the cron user (in that group) can delete them.
* Log out and back in, then check with `groups` that the account's group is listed.

### 2. sshd

```bash
sed "s/<sftp user>/$SFTP_USER/g" sshd_relay.conf | sudo tee /etc/ssh/sshd_config.d/sftp_relay.conf
sudo sshd -t
sudo sshd -T -C user=$SFTP_USER,host=x,addr=1.2.3.4 | grep -i -e passwordauthentication -e forcecommand -e chrootdirectory
sudo systemctl reload ssh
```

* Keep `PasswordAuthentication no` globally: only the SFTP account logs in with a password.
* `sshd -T -C` shows the settings that apply to the account. Expect `passwordauthentication yes`, `forcecommand internal-sftp -u 0002 -d /upload` and `chrootdirectory /srv/sftp/<sftp user>`.
* Keep your current SSH session open until a new login works.

### 3. fail2ban

```bash
sudo apt install fail2ban
```

Blocks repeated failed logins. Its default `sshd` jail is enough.

### 4. Test

From another computer:

```bash
sftp partner@<host>     # works, starts in /upload
ssh partner@<host>      # refused
```

## Relay

### 1. Install

```bash
sudo apt install lftp
git clone <this repo> ~/SFTP-relay
cd ~/SFTP-relay
cp .env.example .env
chmod 600 .env
```

Set the real values in `.env`, replacing the placeholders. It is in `.gitignore`.

### 2. Test

Upload a file over SFTP, then backdate it to skip the 5 min wait and run the relay:

```bash
sudo touch -d '10 minutes ago' /srv/sftp/<sftp user>/upload/<file>
./relay.sh
cat logs/relay.log
```

The log should end with `done`, the file should be on the FTP server and `upload/` empty.

### 3. Cron

```bash
# Moves files received over SFTP to the FTP server
# Every 10 min
*/10 * * * * /usr/bin/flock -w 0 ~/sftp_relay.lock ~/SFTP-relay/relay.sh
```

* `lftp mirror` lists folders on the FTP server that are no longer in `upload/` as `To be removed`. Nothing is removed: never add `--delete`.

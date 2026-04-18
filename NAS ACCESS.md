# How to access Network Attached Storage (NAS)

These instructions tell you how to mount your NAS so that recording-analyzer.sh can access those files. These instructions apply to both Windows computers (with WSL installed) and Linux computers.

## Step 1, install the CIFS (Common Internet File System) utility

```bash
sudo apt install cifs-utils
sudo mkdir /mnt/nas
```

## Step 2, create a file in your home directory called cifs.txt

```bash
cat << EOF > ~/.cifs.txt
username=youruser
password=yourpassword
EOF

chmod 600 ~/.cifs.txt
```

Where "youruser" is your username on the NAS and "password" is your password on the NAS.

## Step 3, mount the NAS filesystem

```bash
sudo mount -t cifs //192.168.1.100/sharename /mnt/nas -o credentials=~/.cifs.txt,uid=$(id -u),gid=$(id -g)
```

Where "192.168.1.100" is the IP address of your NAS and "sharename" is the name you assigned to the drive on your NAS.

Once the NAS drive is mapped, you should be able to see your files in the WSL console at /mnt/nas

The only problem with mounting the NAS this way is that it won't be available after you reboot your computer and you'll have to repeat step 3. If you want, you can...

## Step 4, make it permanent

Note your user ID and group ID

```bash
id -u
id -g
```

Edit the /etc/fstab file

```bash
sudo nano /etc/fstab
```

Add the following line to the end of the file

```bash
//192.168.1.100/sharename  /mnt/nas  cifs  credentials=/home/yourusername/.cifs.txt,uid=myuid,gid=mygid  0  0
```

Where "192.168.1.100" is the IP address of your NAS, "sharename" is the name you assigned to the drive on your NAS, "myuid" is your user ID, and "mygid" is your user group. Now your NAS will automatically mount every time you start your computer.

## Unmounting the drive

If you no longer need to access the files on your NAS, you can unmount the drive.

```bash
sudo umount /mnt/nas
```

## 💬 Feedback

Comments, questions, and suggestions are welcome. You can open an issue here: <https://github.com/mcochris/Recording-analyzer/issues>

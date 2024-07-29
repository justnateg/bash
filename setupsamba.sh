#!/bin/bash

# Install expect if not installed
if ! command -v expect &> /dev/null
then
    echo "Expect is not installed. Installing expect..."
    apt update
    apt install -y expect
fi

# Install required packages
echo "Installing Samba and related packages..."
apt install -y samba smbclient cifs-utils

# Create a new group for Samba shares
echo "Creating a new group 'smbshare'..."
groupadd smbshare

# Create a new user for Samba
echo "Creating a new user 'nrg'..."
useradd -M -s /sbin/nologin nrg

# Add the Samba user to the smbshare group
echo "Adding 'nrg' to 'smbshare' group..."
usermod -aG smbshare nrg

# Set Samba password for the user
echo "Setting Samba password for 'nrg'..."
expect <<EOF
spawn smbpasswd -a nrg
expect "New SMB password:"
send "2141\r"
expect "Retype new SMB password:"
send "2141\r"
expect eof
EOF

# Enable the Samba user account
echo "Enabling 'nrg'..."
smbpasswd -e nrg

# Remove the existing smb.conf
echo "Removing the existing smb.conf..."
rm /etc/samba/smb.conf

# Replace with a new smb.conf
echo "Creating a new smb.conf..."
tee /etc/samba/smb.conf > /dev/null <<EOL
[global]
   workgroup = NRGHOME
   server string = Samba Server %v
   security = user
   map to guest = Bad User
   name resolve order = bcast host
   dns proxy = no

   # Performance tuning
   strict allocate = yes
   min receivefile size = 16384
   aio read size = 1
   aio write size = 1

   # Protocol and compatibility
   min protocol = SMB2
   ea support = yes

   # VFS module for macOS compatibility
   vfs objects = fruit streams_xattr
   fruit:metadata = stream
   fruit:model = Macmini
   fruit:veto_appledouble = no
   fruit:posix_rename = yes
   fruit:zero_file_id = yes
   fruit:wipe_intentionally_left_blank_rfork = yes
   fruit:delete_empty_adfiles = yes

   # Included configuration for specific shares
   include = /etc/samba/smb.nrghome.conf
EOL

# Create the include file for individual share configurations
echo "Creating smb.nrghome.conf..."
tee /etc/samba/smb.nrghome.conf > /dev/null <<EOL

[rootfs]
comment = rootfs
public = Yes
path = /
browseable = Yes
read only = No
guest ok = Yes
create mask = 0777
directory mask = 0777
force user = root
EOL

# Reload Samba services
echo "Reloading Samba services..."
systemctl restart smbd nmbd

echo "Samba setup complete."
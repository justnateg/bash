#!/bin/bash

# Variables
CREDENTIALS_FILE="/etc/samba/credentials"
USERNAME="nrg"
PASSWORD="2141"
SMB_VERSION="3.0"

# Install expect if not installed
if ! command -v expect &> /dev/null; then
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
send "${PASSWORD}\r"
expect "Retype new SMB password:"
send "${PASSWORD}\r"
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
hostname=$(hostname)
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

[rootfs - ${hostname}]
   path = /
   guest ok = no
   valid users = @nrg
   browsable = yes
   writable = yes
   read only = no
   create mask = 0664
   directory mask = 0775
   force group = smbshare
   vfs objects = catia fruit streams_xattr
EOL

# Reload Samba services
echo "Reloading Samba services..."
systemctl restart smbd nmbd

echo "Samba setup complete."

# Function to check if a package is installed
function is_installed {
    dpkg -l "$1" &> /dev/null
}

# Install cifs-utils if not installed
if ! is_installed cifs-utils; then
    echo "Installing cifs-utils..."
    sudo apt-get update
    sudo apt-get install -y cifs-utils
else
    echo "cifs-utils is already installed."
fi

# Create the credentials file
echo "Creating the credentials file..."
sudo bash -c "echo 'username=${USERNAME}' > ${CREDENTIALS_FILE}"
sudo bash -c "echo 'password=${PASSWORD}' >> ${CREDENTIALS_FILE}"
sudo chmod 600 ${CREDENTIALS_FILE}

# Verify the credentials file was created
if [ ! -f "${CREDENTIALS_FILE}" ]; then
    echo "Failed to create the credentials file."
    exit 1
fi

# Define new mount points and their corresponding IP addresses and share names
declare -A MOUNT_POINTS
MOUNT_POINTS["10.0.0.25"]="nvme"
MOUNT_POINTS["10.0.0.100"]="nvme"
MOUNT_POINTS["10.0.0.206"]="media"

# Iterate over mount points and add them to fstab
for IP in "${!MOUNT_POINTS[@]}"; do
  SHARE_NAME="${MOUNT_POINTS[$IP]}"
  MOUNT_POINT="/mnt/smb/${IP}"
  FSTAB_ENTRY="//${IP}/${SHARE_NAME} ${MOUNT_POINT} cifs _netdev,x-systemd.automount,noatime,uid=100000,gid=110000,dir_mode=0770,file_mode=0770,credentials=${CREDENTIALS_FILE},iocharset=utf8,vers=${SMB_VERSION} 0 0"
  
  if ! grep -qF "$FSTAB_ENTRY" /etc/fstab; then
    echo "Adding Samba share to /etc/fstab..."
    sudo bash -c "echo '$FSTAB_ENTRY' >> /etc/fstab"
  else
    echo "Samba share already exists in /etc/fstab."
  fi
  
  # Create mount point directory
  if [ ! -d "$MOUNT_POINT" ]; then
    echo "Creating mount point directory $MOUNT_POINT..."
    sudo mkdir -p $MOUNT_POINT
  else
    echo "Mount point directory $MOUNT_POINT already exists."
  fi
done

# Mount the shares
echo "Mounting Samba shares..."
sudo mount -a

# Verify the mounts
for IP in "${!MOUNT_POINTS[@]}"; do
  MOUNT_POINT="/mnt/smb/${IP}"
  if mountpoint -q $MOUNT_POINT; then
    echo "Samba share mounted successfully at $MOUNT_POINT."
  else
    echo "Failed to mount Samba share at $MOUNT_POINT."
  fi
done

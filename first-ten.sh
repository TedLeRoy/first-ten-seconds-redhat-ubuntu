#!/bin/bash

# bash script to set minimal security on new installations of Ubuntu
# Rocky Linux and CentOS Linux. Written using Ubuntu 20.04 and Rocky 
# Linux 8 and CentOS 8.
# Written by Ted LeRoy with help from Google and the Linux community
# Follow or contribute on GitHub here:
# https://github.com/TedLeRoy/first-ten-seconds-centos-ubuntu
# Inspired by Jerry Gamblin's post:
# https://jerrygamblin.com/2016/07/13/my-first-10-seconds-on-a-server/
# Also by Bryan Kennedy's post which no longer seems to be available
# This script has been verified by shellcheck. Thanks koalaman!
# https://github.com/koalaman/shellcheck

# Defining Colors for text output if to stdout
if [[ -t 1 ]]; then
  red=$( tput setaf 1 );
  yellow=$( tput setaf 3 );
  green=$( tput setaf 2 );
  normal=$( tput sgr 0 );
fi

# Determine OS name and store it in "osName" variable
osName=$( cat /etc/*os-release | grep ^NAME | cut -d '"' -f 2 );

# Checking if running as root. If yes, asking to change to a non-root user.
# This verifies that a non-root user is configured and is being used to run
# the script.

if [ ${UID} == 0  ]
then
  echo "${red}
  You're running this script as root user.
  Please configure a non-root user and run this
  script as that non-root user.
  Please do not start the script using sudo, but
  enter sudo privileges when prompted.
  ${normal}"
  #Pause so user can see output
  sleep 1
  exit
fi

#################################################
#                 Ubuntu Section                #
#################################################

# If OS is Ubuntu, apply the security settings for Ubuntu

if [ "$osName" == "Ubuntu" ]
then
  echo "${green}  You're running $osName Linux. $osName security
  first measures will be applied.

  You will be prompted for your sudo password.
  Please enter it when asked.
  ${normal}
  "
  ##############################################
  #            Ubuntu Firewall Section         #
  ##############################################
  
  # Enabling ufw firewall and making sure it allows SSH
  echo "${yellow}  Enabling ufw firewall. Ensuring SSH is allowed.
  ${normal}"
  sudo ufw allow ssh
  sudo ufw --force enable
  echo "${green}
  Done configuring ufw firewall.
  ${normal}"
  #Pausing so user can see output
  sleep 1

  ##############################################
  #              Ubuntu SSH Section            #
  ##############################################

  # Checking whether an authorized_keys file exists in logged in user's account.
  # If so, the assumption is that key based authentication is set up.
  if [ -f /home/"$USER"/.ssh/authorized_keys ]
  then
    echo "${yellow}  
    Locking down SSH so it will only permit key-based authentication.
    ${normal}"
    echo -n "${red}  
    Are you sure you want to allow only key-based authentication for SSH? 
    PASSWORD AUTHENTICATION WILL BE DISABLED FOR SSH ACCESS!
    (y or n):${normal} " 
    read -r answer
    # Putting relevant lines in /etc/ssh/sshd_config.d/11-sshd-first-ten.conf file
    if [ "$answer" == "y" ] || [ "$answer" == "Y" ] ;then
      echo "${yellow}
      Adding the following lines to a file in sshd_config.d
      ${normal}"
      echo "DebianBanner no
DisableForwarding yes
PermitRootLogin no
IgnoreRhosts yes
PasswordAuthentication no" | sudo tee /etc/ssh/sshd_config.d/11-sshd-first-ten.conf 
      echo "${yellow}
      Reloading ssh
      ${normal}"
      # Restarting ssh daemon
      sudo systemctl reload ssh
      echo "${green}
      ssh has been restarted.
      # Pause so user can see output
      sleep 1
      ${normal}"

    else
      # User chose a key other than "y" for configuring ssh so it will not be set up now
      echo "${red}
      You have chosen not to disable password based authentication at this time.
      Please do so yourself or re-run this script when you're prepared to do so.
      ${normal}"
      # Pausing so user can see output
      sleep 1
    fi

  else
    # The check for an authorized_keys file failed so it is assumed key based auth is not set up
    # Skipping this configuration and warning user to do it for herself
    echo "${red}  
    It looks like SSH is not configured to allow key based authentication.
    Please enable it and re-run this script.${normal}"
  fi

  ##############################################
  #          Ubuntu fail2ban Section           #
  ##############################################

  # Installing fail2ban and networking tools (includes netstat)
  echo "${yellow}
  Installing fail2ban and networking tools.
  ${normal}"
  sudo apt install fail2ban net-tools -y
  echo "${green}
  fail2ban and networking tools have been installed.
  ${normal}"
  # Setting up the fail2ban jail for SSH
  echo "${yellow}
  Configuring fail2ban to protect SSH.

  Entering the following into /etc/fail2ban/jail.local
  ${normal}"
  echo "# Default banning action (e.g. iptables, iptables-new,
# iptables-multiport, shorewall, etc) It is used to define
# action_* variables. Can be overridden globally or per
# section within jail.local file

[ssh]

enabled  = true
banaction = iptables-multiport
port     = ssh
filter   = sshd
logpath  = /var/log/auth.log
maxretry = 5
findtime = 43200
bantime = 86400" | sudo tee /etc/fail2ban/jail.local
  # Restarting fail2ban
  echo "${green}
  Restarting fail2ban
  ${normal}"
  sudo systemctl restart fail2ban
  echo "${green}
  fail2ban restarted
  ${normal}"
  # Tell the user what the fail2ban protections are set to
  echo "${green}
  fail2ban is now protecting SSH with the following settings:
  maxretry: 5
  findtime: 12 hours (43200 seconds)
  bantime: 24 hours (86400 seconds)
  ${normal}"
  # Pausing so user can see output
  sleep 1

  ##############################################
  #           Ubuntu Overview Section          #
  ##############################################

#Explain what was done
echo "${green}
Description of what was done:
1. Ensured a non-root user is set up.
2. Ensured non-root user also has sudo permission (script won't continue without it).
3. Ensured SSH is allowed.
4. Ensured ufw firewall is enabled.
5. Locked down SSH if you chose y for that step.
   a. Set SSH not to display banner
   b. Disabled all forwarding
   c. Disabled root login over SSH
   d. Ignoring rhosts
   e. Disabled password authentication
6. Installed fail2ban and configured it to protect SSH.
[note] For a default Ubuntu server installation, automatic security updates are enabled so no action was taken regarding updates.
${normal}"

#################################################
#          CentOS / Red Hat Section             #
#################################################

elif [ "$osName" == "CentOS Linux" ] || [ "$osName" == "Red Hat Enterprise Linux" ] || [ "$osName" == "Rocky Linux" ] || [ "$osName" == "CentOS Stream" ] || [ "$osName" == "AlmaLinux" ]
then

  # Determine wheter Extra Packages for Enterprise Linux (epel) repo is supported.
  # Needed for fail2ban installation later.
  epelStat=$( dnf list installed | grep epel-release | cut -d "." -f1 )

  echo "${green}  You're running $osName. $osName security first 
  measures will be applied.

  You will be prompted for your sudo password.
  Please enter it when asked.
  ${normal}"
  #Pause so user can see output
  sleep 1
  
  ##############################################
  #            CentOS Firewall Section         #
  ##############################################

  # Enabling firewalld firewall and making sure it allows SSH
  echo "${yellow}  Enabling firewalld firewall. Ensuring SSH is allowed.
  ${normal}"

  echo "${yellow}  Configuring firewalld to disallow Zone Drifting
  ${normal}"
  sudo sed -i.bak 's/#\?\(AllowZoneDrifting*\).*$/\1=no/' /etc/firewalld/firewalld.conf

  OUTPUT=$(sudo firewall-cmd --permanent --list-all | grep services)
  if echo "$OUTPUT" | grep -q "ssh"; then
    echo "${green}
    firewalld is already configured to allow SSH
    ${normal}"
    echo "${yellow}
    Ensuring firewalld is running
    ${normal}"
    sudo systemctl start firewalld
    echo "${green}
    Done configuring firewalld
    ${normal}"
    #Pause so user can see output
    sleep 1
  else
    echo "${yellow}
    Adding SSH to allowed protocols in firewalld
    ${normal}"
    sudo firewall-cmd --permanent --add-service=ssh
    echo "${yellow}
    Restarting firewalld
    ${normal}"
    sudo systemctl restart firewalld
    echo "${green}
    Done configuring firewalld
    ${normal}"
    #Pause so user can see output
    sleep 1
  fi

  ##############################################
  #              CentOS SSH Section            #
  ##############################################

  # Checking whether an authorized_keys file exists in logged in user's account.
  # If so, the assumption is that key based authentication is set up.
  if [ -f /home/"$USER"/.ssh/authorized_keys ]
  then
    echo "${yellow}
    Locking down SSH so it will only permit key-based authentication.
    ${normal}"
    echo -n "${red}
    Are you sure you want to allow only key-based authentication for SSH?
    PASSWORD AUTHENTICATIN WILL BE DISABLED FOR SSH ACCESS!
    (y or n):${normal} "
    read -r answer
    # Putting relevant lines in /etc/ssh/sshd_config.d/11-sshd-first-ten.conf file
    if [ "$answer" == "y" ] || [ "$answer" == "Y" ] ;then
      echo "${yellow}
      Making modifications to /etc/ssh/sshd_config.
      ${normal}"
      # Making backup copy 1 of sshd_config
      sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.0
      echo "
# Disabling all forwarding.
# [note] This setting overrides all other forwarding settings!
# This entry was added by first-ten.sh
DisableForwarding yes" | sudo tee -a /etc/ssh/sshd_config
      sudo sed -i.bak -e 's/#IgnoreRhosts/IgnoreRhosts/' -e 's/IgnoreRhosts\s\no/IgnoreRhosts\s\yes/' /etc/ssh/sshd_config
      sudo sed -i.bak1 '/^PermitRootLogin/s/yes/no/' /etc/ssh/sshd_config
      sudo sed -i.bak2 '/^PasswordAuthentication/s/yes/no/' /etc/ssh/sshd_config
      echo "${yellow}
      Reloading ssh
      ${normal}"
      # Restarting ssh daemon
      sudo systemctl reload sshd
      echo "${green}
      ssh has been restarted.
      ${normal}"
      #Pause so user can see output
      sleep 1
    else
      # User chose a key other than "y" for configuring ssh so it will not be set up now
      echo "${red}
      You have chosen not to disable password based authentication at this time and
      not to apply the other SSH hardening steps.
      Please do so yourself or re-run this script when you\'re prepared to do so.
      ${normal}"
      #Pause so user can see output
      sleep 1
  fi

  else
    # The check for an authorized_keys file failed so it is assumed key based auth is not set up
    # Skipping this configuration and warning user to do it for herself
    echo "${red}
    It looks like SSH is not configured to allow key based authentication.
    Please enable it and re-run this script.${normal}"
    #Pause so user can see output
    sleep 1
  fi

  ##############################################
  #          CentOS fail2ban Section           #
  ##############################################

  # If epel not supported add it before installing fail2ban
  if [ "$epelStat" != "epel-release" ]
    then
    echo "Installing epel-release repository to support fail2ban installation"
    echo sudo dnf install epel-release -y
  fi

  # Installing fail2ban and networking tools (includes netstat)
  echo "${yellow}
    Installing fail2ban.
    ${normal}"
    sudo dnf install fail2ban -y
      echo "${green}
      fail2ban has been installed.
      ${normal}"
      # Setting up the fail2ban jail for SSH
      echo "${yellow}
      Configuring fail2ban to protect SSH.
      Entering the following into /etc/fail2ban/jail.local
      ${normal}"
      echo "# Default banning action (e.g. iptables, iptables-new,
# iptables-multiport, shorewall, etc) It is used to define
# action_* variables. Can be overridden globally or per
# section within jail.local file

[ssh]

enabled  = true
banaction = iptables-multiport
port     = ssh
filter   = sshd
logpath  = /var/log/auth.log
maxretry = 5
findtime = 43200
bantime = 86400" | sudo tee /etc/fail2ban/jail.local
      # Restarting fail2ban
      echo "${green}
      Restarting fail2ban
      ${normal}"
      sudo systemctl restart fail2ban
      echo "${green}
      fail2ban restarted
      ${normal}"
      # Tell the user what the fail2ban protections are set to
      echo "${green}
      fail2ban is now protecting SSH with the following settings:
      maxretry: 5
      findtime: 12 hours (43200 seconds)
      bantime: 24 hours (86400 seconds)
      ${normal}"
      #Pause so user can see output
      sleep 1

  ##############################################
  #            CentOS Updates Section          #
  ##############################################

  # Configuring automatic updates for CentOS / Red Hat
  echo "${yellow}
  Running system update and upgrade.
  ${normal}"
  sudo dnf upgrade
  echo "${green}
  Upgrade complete.
  ${normal}"
  echo "${yellow}
  Installing Auto-upgrade (dnf-automatic)
  ${normal}"
  sudo dnf install dnf-automatic -y
  echo "${green}
  dnf-automatic installed.
  ${normal}"
  echo "${yellow}
  Enabling automatic updates (dnf-automatic.timer)
  ${normal}"
  sudo systemctl enable --now dnf-automatic.timer
  echo "${green}
  Automatic updates enabled.
  ${normal}"
  echo "${green}
  You can check timer by running:
  sudo systemctl status dnf-automatic.timer
  Look for \"loaded\" under the Loaded: line
  and \"active\" under the Active: line.
  ${normal}"
  #Pause so user can see output
  sleep 1


  ##############################################
  #           CentOS Overview Section          #
  ##############################################

#Explain what was done
echo "${green}
Description of what was done:
1. Ensured a non-root user is set up.
2. Ensured non-root user also has sudo permission (script won't continue without it).
3. Ensured SSH is allowed.
4. Ensured firewlld firewall is enabled.
5. Locked down SSH if you chose y for that step.
   a. Disabled all forwarding
   b. Disabled root login over SSH
   c. Ignoring rhosts
   d. Disabled password authentication
6. Installed fail2ban and configured it to protect SSH.
[note] For a default Ubuntu server installation, automatic security updates are enabled so no action was taken regarding updates.
${normal}"

####################################################
#  If Neither CentOS / Red Hat or Ubuntu is found  #
####################################################

else
  echo "${red}
  I'm not sure what operating system you're running.
  This script has only been tested for CentOS / Red Hat 
  Rocky Linux, and Ubuntu.
  Please run it only on those operating systems.
  ${normal}"
fi

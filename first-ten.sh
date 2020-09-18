#!/bin/bash

# bash script to set minimal security on new installations of Ubuntu
# and CentOS Linux. Written using Ubuntu 20.04 and CentOS 8.
# Written by Ted LeRoy with help from Google and the Linux community
# Follow or contribute on GitHub here:
# https://github.com/TedLeRoy/first-ten-seconds-centos-ubuntu
# Inspired by Jerry Gamblin's post:
# https://jerrygamblin.com/2016/07/13/my-first-10-seconds-on-a-server/

# Defining Colors for text output
red=$( tput setaf 1 );
yellow=$( tput setaf 3 );
green=$( tput setaf 2 );
normal=$( tput sgr 0 );

# Determine OS name and store it in "osName" variable
osName=`cat /etc/*os-release | grep ^NAME | cut -d '"' -f 2`

# Checking if running as root. If yes, asking to change to a non-root user.
if [ ${UID} == 0  ]
then

  echo "${red}
  You're running this script as root user.
  Please configure a non-root user and run this
  script as that non-root user.
  ${normal}"
  exit
fi

if [ "$osName" == 'Ubuntu' ]
then

  echo "${green}  You're running Ubuntu Linux. Ubuntu security
  first measures will be applied.

  You will be prompted for your sudo password.
  Please enter it when asked.
  ${normal}
  "

  echo "${yellow}  Enabling ufw firewall. It will allow only ssh inbound.
  ${normal}"
  sudo ufw allow ssh
  sudo ufw --force enable
  echo "${green}
  Done configuring ufw firewall.
  ${normal}"

elif [ "$osName" == "CentOS Linux" ]
then

  echo "${green}  You're running CentOS Linux. CentOS security
  first measures will be applied.

  You will be prompted for your sudo password.
  Please enter it when asked.
  ${normal}
  "

fi

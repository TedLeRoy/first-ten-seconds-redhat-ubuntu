![First-ten-post-run](https://i.ibb.co/4N5QXww/After-Running-Script.png)

# first-ten-seconds-centos-ubuntu

A bash script to help secure a new CentOS 8, Red Hat 8, or Ubuntu 20.04 server quickly and easily.

### Background

This doesn't "lock down" your server completely, but improves the security posture of a new Red Hat 8, CentOS 8 or Ubuntu 20.04 server so you can take more time with further improvements if you need to.

Inspired by Jerry Gamblin's blog post: https://jerrygamblin.com/2016/07/13/my-first-10-seconds-on-a-server/ as well as Bryan Kennedy's post: https://plusbryan.com/my-first-5-minutes-on-a-server-or-essential-security-for-linux-servers, and DigitalOcean guides, CentOS, Red Hat, and Ubuntu security best practices, and things I like to do myself for new servers.

The script will determine if it's being run on a CentOS, Red Hat, or Ubuntu server and will run commands appropriate for the OS.

It is strongly recommended to only run this on clean installs after a non-root user with sudo permission has been set up and key based ssh authentication is configured and tested for that user. 

The following tutorials can help you set up key based authentication:

My YouTube series, part 1 through 7 for key based authentication on Ubuntu: https://www.youtube.com/watch?v=ugpAr5fhA1s&t=16s

Digital Ocean CentOS 8 Key Based Authentication tutorial: https://www.digitalocean.com/community/tutorials/how-to-set-up-ssh-keys-on-centos-8

Digital Ocean Ubuntu 20.04 Key Based Authentication tutorial: https://www.digitalocean.com/community/tutorials/how-to-set-up-ssh-keys-on-ubuntu-20-04

This script is being created in support of my Linux Security course to give students a jump on securing newly built CentOS and Ubuntu servers.

### [Project Goals](#project-goals)

This project seeks to roll a few common security best practices for new servers into a script that will determine whether it's being run on CentOS or Ubuntu and will run the security related commands appropriate for the OS it's being run on.

### What It Does

This script will do the following for Ubuntu:

1. Ensure a non-root user is set up.
2. Ensure non-root user also has sudo permission (script won't continue without it).
3. Ensure SSH is allowed through the ufw firewall.
4. Ensure ufw firewall is enabled.
5. Lock down SSH if you choose y for that step.

   1. Set SSH not to display banner
   1. Disable all forwarding
   1. Disable root login over SSH
   1. Ignore rhosts
   1. Disable password authentication
   
6. Install fail2ban and configured it to protect SSH. 
(note) For a default Ubuntu server installation, automatic security updates are enabled so no action was taken regarding updates.

The script will do the following for CentOS:

1. Ensure a non-root user is set up.
2. Ensure non-root user also has sudo permission (script won't continue without it).
3. Ensure SSH is allowed through the firewalld firewall.
4. Ensure firewalld firewall is enabled.
5. Locked down SSH if you choose y for that step.

   1. Set SSH not to display banner
   1. Disable all forwarding
   1. Disable root login over SSH
   1. Ignore rhosts
   1. Disable password authentication

6. Install fail2ban and configured it to protect SSH.
7. Ensure automatic security updates are configured.

### Prerequisites

You must have sudo permissions to run the commands inside the script.

The script should not be run as root, but the user running it will be prompted for sudo credentials once it runs. sudo password should be entered to continue.

### Warning

Be sure you have read and understand what this file does before running it.

You can read the man page for each command and option to see what it does.

Any time the creator of a script says it has to be run with sudo permissions or as root, understand why and use caution.

***This script has to be run by a user with sudo permissions because the system update, firewall, and ssh related commands it uses must be run as root. It should be run by a non-root user but sudo credentials should be provided when prompted.***

### Usage

The latest version of this script can be run with the following single line at the Linux terminal on any CentOS 8, Red Hat 8, or Ubuntu 20.04 new installation after a non-root user with sudo privileges has been set up and key based authentication for that user using SSH configured:

`bash <(curl -s https://raw.githubusercontent.com/TedLeRoy/first-ten-seconds-centos-ubuntu/master/first-ten.sh)`

Alternatively, you can clone the full repository locally or just copy and run the first-ten.sh script from the link below.

`https://raw.githubusercontent.com/TedLeRoy/first-ten-seconds-centos-ubuntu/master/first-ten.sh`

You could use the following commands (you may have to install wget first if you did a minimal install):

```
wget https://raw.githubusercontent.com/TedLeRoy/first-ten-seconds-centos-ubuntu/master/first-ten.sh
cmhod +x first-ten.sh
./first-ten.sh
```

You can also follow the traditional method for GitHub projects and create your own clone then run from that.

```
git clone https://github.com/TedLeRoy/first-ten-seconds-centos-ubuntu.git
cd first-ten-seconds-centos-ubuntu
./first-ten.sh
```

### Issues, Feature Requests, Input

Please report issues, request features, or provide your input or feedback about the script [here](https://github.com/TedLeRoy/first-ten-seconds-centos-ubuntu/issues).

# first-ten-seconds-centos-ubuntu

A simple bash script to help secure a new CentOS or Ubuntu server quickly and easily.

### Background

This doesn't "lock down" your server completely, but improves the security posture of a new Red Hat 8, CentOS 8 or Ubuntu 20.04 server so you can take your time with further improvements.

Inspired by Jerry Gamblin's blog post: https://jerrygamblin.com/2016/07/13/my-first-10-seconds-on-a-server/ as well as Bryan Kennedy's post: https://plusbryan.com/my-first-5-minutes-on-a-server-or-essential-security-for-linux-servers, DigitalOcean guides, and things I like to do myself for new servers.

The script will determine if it's being run on a CentOS, Red Hat, or Ubuntu server and to run commands appropriate for the OS.

This repo will perform several functions recommended for a new server and will do so for either CentOS or Ubuntu.

It is strongly recommended to only run this on clean installs after a non-root user with sudo permission has been set up and key based ssh authentication is configured and tested for that user. 

This script is being created in support of my Linux Security course to give students a jump on securing newly built CentOS and Ubuntu servers.

### [Project Goals](#project-goals)

This project seeks to roll a few common security best practices for new servers into a script that will determine whether it's being run on CentOS or Ubuntu and will run the commands appropriate for the OS it's being run on.

### Prerequisites

You must have sudo permissions to run the commands inside the script.

The script should not be run as root, but the user running it will be prompted for sudo credentials once it runs. sudo password should be entered to continue.

### Warning

Be sure you have read and understand what this file does before running it.

You can read the man page for each command and option to see what it does.

Any time the creator of a script says it has to be run with sudo permissions or as root, understand why and use caution.

***This script has to be run with sudo because the system update, firewall, and ssh related commands it uses must be run as root.***

### Usage

The latest version of this script can be run with the following single line at the Linux terminal:

bash <(curl -s https://raw.githubusercontent.com/TedLeRoy/first-ten-seconds-centos-ubuntu/master/first-ten.sh)

Alternatively, you can copy the full repository locally or just copy and run the first-ten.sh script from the link above.

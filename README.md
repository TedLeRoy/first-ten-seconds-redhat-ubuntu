# first-ten-seconds-centos-ubuntu

A simple bash script to help secure a new CentOS or Ubuntu server quickly and easily.

Inspired by Jerry Gamblin's blog post: https://jerrygamblin.com/2016/07/13/my-first-10-seconds-on-a-server/

Modified to determine if it's being run on a CentOS or Ubuntu server and to run commands appropriate for the OS.

### Background

This repo will perform several functions recommended for a new server and will do so for either CentOS or Ubuntu.

It is strongly recommended to only run this on clean installs. 

This script is being created in support of my Linux Security course to give students a jump on securing newly built CentOS and Ubuntu servers.

### [Project Goals](#project-goals)

This project seeks to roll a few common security best practices for new servers into a script that will determine whether it's being run on CentOS or Ubuntu and will run the commands appropriate for the OS it's being run on.

### Prerequisites

You must have sudo permissions to run the commands inside the script.

You must set the file executable.

The script should not be run as root, but the user running it will be prompted for sudo credentials once it runs. sudo password should be entered to continue.

### Warning

Be sure you have read and understand what this file does before running it.

You can read the man page for each command and option to see what it does.

Any time the creator of a script says it has to be run with sudo permissions or as root, inderstand why and use caution.

***This script has to be run with sudo because the apt and firewall commands it uses must be run as root.***


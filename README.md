# pi-hole
Workflow for the the testing &amp; deployment of pi-hole on a home router.
## Goal: Stand up a single-node Kubernetes instance (k3s) on the Raspberry Pi 4b & deploy pi-hole on it
### Concepts:
- Linux CLI Basics (ssh, systemd, vim, ping)
- Networking (DHCP vs. Static IP, subnets / CIDR notation, DNS Resolution, LoadBalancer)
- Kubernetes (Pod, Deployment, Service, PVC, Secret, Namespace)
### Language:
- Bash
- YAML
### Items
- Raspberry Pi 4b 4GB
- Modem (Xfinity XB7 Modem)
- Router(Netgear Nighthawk R7350)
- Ethernet Cables 
- Coffeeeeee (basecamp beans)

### Notes
- Work was done on Rzyen 5 7600 running Ubuntu 24.04.4 LTS
- Tasking was co-authored using Claude (solely for education & technical support -- all code was human-written)
- Reference documents can be found on the [pi-hole webpage](https://pi-hole.net/) & [pi-hole Git repo](https://github.com/pi-hole/pi-hole)


# Work Done
##TODO
Add Summary of steps here. Numbered. Perhaps hyperlinked.
## Start by flashing the Raspi with Ubuntu Server 24.04 LTS (ARM64) from microSD
### Pull Software
Install Raspberry Pi Imager onto the Working PC (Ryzen 5 in my case)
Either use [the GUI](https://www.raspberrypi.com/software/) or pull from apt:
'''
sudo apt update
sudo apt install rpi-imager
'''
### Flash MicroSD
- Mount MicroSD to Work PC & run Raspberry Pi Imager
- Before writing, use Gear icon (settings) to pre-configure **hostname, SSH enabled, username/password**
- Write to the MicroSD
#### Notes
Booting from SSD is ideal due to our Kubernetes deployment, however since our use case is so small, a microSD card will suffice in the short term
- Reasons to avoid MicroSD:
  - Sequential write vs. Random-Access
  - Long term memory degration

## Boot & Configure Raspi
- Insert MicroSD into Raspi
- Connect Ethernet, Power, & the flashed MicroSD card
**NOTE: ENSURE RASPI & WORKPC ARE CONNECTED TO SAME INTERNET DEVICE**
If the PC is plugged into the Modem but the Raspi is on a Router/Switch, you run the 


k3s is installed

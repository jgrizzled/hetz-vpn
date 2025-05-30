#cloud-config

users:
  - name: admin
    primary_group: admin
    groups: wheel
    shell: /bin/bash
    lock_passwd: true
    sudo: ALL=(ALL) NOPASSWD:ALL
    ssh_authorized_keys:
      - ${ssh_public_key}

yum_repos:
  epel-release:
    name: Extra Packages for Enterprise Linux $releasever - $basearch
    baseurl: https://download.fedoraproject.org/pub/epel/$releasever/Everything/$basearch
    enabled: true
    gpgcheck: true
    gpgkey: https://download.fedoraproject.org/pub/epel/RPM-GPG-KEY-EPEL-$releasever

# Update the system and install necessary packages
package_update: true
package_upgrade: true
packages:
  - dnf-automatic
  - firewalld
  - yum-utils
  - wireguard-tools
  - iptables-services

write_files:
  - path: /etc/dnf/automatic.conf
    content: |
      [commands]
      apply_updates = true
      upgrade_type = security
      reboot = never
  - path: /etc/ssh/sshd_config.d/cloudinit.conf
    content: |
      Port ${ssh_port}
      PasswordAuthentication no
      PermitRootLogin no
      X11Forwarding no
      MaxAuthTries 10
      AllowTcpForwarding yes
      AllowAgentForwarding no
  - path: /etc/sysctl.d/99-wireguard.conf
    content: |
      # Enable IP forwarding for Wireguard
      net.ipv4.ip_forward = 1
      net.ipv6.conf.all.forwarding = 1
  - path: /etc/wireguard/.placeholder
    content: |
      # Placeholder file to ensure /etc/wireguard directory exists
      # The actual wg0.conf will be synced via Ansible

# Make sure the hostname is set correctly
hostname: ${hostname}
preserve_hostname: true

timezone: ${tz}

runcmd:
  - [systemctl, daemon-reload]
  - [systemctl, restart, sshd]
  - [systemctl, enable, --now, wg-quick@wg0]

  # Configure firewall
  - [systemctl, enable, --now, firewalld]
  # Remove default services we don't need
  - firewall-cmd --permanent --zone=public --remove-service=dhcpv6-client
  - firewall-cmd --permanent --zone=public --remove-service=cockpit
  # Add SSH port
  - firewall-cmd --permanent --zone=public --add-port=${ssh_port}/tcp
  # Add rate limiting for SSH (10 connections per minute)
  - firewall-cmd --permanent --zone=public --add-rich-rule='rule port port="${ssh_port}" protocol="tcp" accept limit value="10/m"'
  # Rate limit ICMP (ping) - 1 ping per second
  - firewall-cmd --permanent --zone=public --add-rich-rule='rule protocol value="icmp" accept limit value="1/s"'

  # Enable masquerading for NAT functionality
  - firewall-cmd --permanent --zone=public --add-masquerade

  - firewall-cmd --permanent --zone=internal --add-source=10.0.0.0/8
  # Enable masquerading in internal zone for VPN traffic
  - firewall-cmd --permanent --zone=internal --add-masquerade
  # Add Wireguard port
  - firewall-cmd --permanent --zone=public --add-port=${vpn_port}/udp
  # Allow forwarding for Wireguard subnet
  - firewall-cmd --permanent --zone=public --add-rich-rule='rule family="ipv4" source address="10.0.0.0/8" accept'
  # Add Wireguard interface to internal zone
  - firewall-cmd --permanent --zone=internal --add-interface=wg0
  # Enable forwarding inside the internal zone
  - firewall-cmd --permanent --zone=internal --add-forward
  # Create a policy that explicitly allows forwarding from VPN clients (internal zone)
  # to the internet-facing interface (public zone)
  - firewall-cmd --permanent --new-policy=vpn-to-internet
  - firewall-cmd --permanent --policy=vpn-to-internet --set-target=ACCEPT
  - firewall-cmd --permanent --policy=vpn-to-internet --add-ingress-zone=internal
  - firewall-cmd --permanent --policy=vpn-to-internet --add-egress-zone=public
  # Enable IP forwarding
  - [sysctl, --system]

  # Set up Wireguard directory permissions
  - [mkdir, -p, /etc/wireguard]
  - [chmod, 700, /etc/wireguard]
  - [chown, root:root, /etc/wireguard]

  # Enable automatic updates
  - [systemctl, enable, --now, dnf-automatic.timer]

  # Bounds the amount of logs that can survive on the system
  - [
      sed,
      "-i",
      "s/#SystemMaxUse=/SystemMaxUse=3G/g",
      /etc/systemd/journald.conf,
    ]
  - [
      sed,
      "-i",
      "s/#MaxRetentionSec=/MaxRetentionSec=1week/g",
      /etc/systemd/journald.conf,
    ]

  # Reload firewall to apply all changes
  - firewall-cmd --reload

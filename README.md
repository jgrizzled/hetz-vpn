# Hetzner VPN

Spin up a Wireguard VPN server on Hetzner with Terraform and Ansible.

## Prerequisites

- [Terraform](https://www.terraform.io/downloads)
- [Ansible](https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html)
- [Wireguard tools](https://www.wireguard.com/install/) (for client key generation)
- Hetzner Cloud API token

## Initial Setup

### 1. Create Hetzner API token

- Go to https://console.hetzner.cloud/projects
- Create a new project
- Click on the project
- Navigate to Security -> API Tokens
- Generate new token with Read & Write access

### 2. Configuration

Copy the example configuration file and fill in your details:

```bash
cp config-example.json config.auto.tfvars.json
```

Edit `config.auto.tfvars.json` with your settings:

- `ssh_public_key`: Your SSH public key for server access
- `hcloud_token`: Your Hetzner Cloud API token
- `location`: Server location (ash, hil, fsn1, nbg1, hel1, sin)
- `ssh_allowed_ips`: IPs allowed to SSH to the server (default: all)
- `vpn_allowed_ips`: IPs allowed to connect to VPN (default: all)
- `instance_type`: Hetzner Cloud instance type (default: cpx11)

### 3. Bootstrap

Run the bootstrap script to create and configure your VPN server:

```bash
./bootstrap.sh
```

This will:

1. Create a Hetzner server with Terraform
2. Install and configure Wireguard via Ansible
3. Generate server keys automatically
4. Create a local `wg0.conf` file with the server configuration
5. Save server keys to `server_private.key` and `server_public.key`

Next, add clients, then run `./sync.sh` to sync the server configuration.

## Adding Clients

### Generate Client Configs

Use the provided script to automatically generate client configurations:

```bash
./generate-client.sh john-laptop 10.0.0.2
./generate-client.sh jane-phone 10.0.0.3
```

This will:

- Generate a new client configuration file (e.g., `john-laptop.conf`) to be imported into your Wireguard client
- Add the client to server configuration in wg0.conf

### Sync Configuration

After adding clients, sync the configuration to the server:

```bash
./sync.sh
```

## Cleanup

To destroy the server and resources:

```bash
terraform destroy
rm *.conf
```

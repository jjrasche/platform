# Runbook: Disaster Recovery

VPS is unresponsive or destroyed.

## Manual Recovery

### 1. Create new VPS
```bash
cd terraform/hetzner
terraform apply
```
Note the new IP address from output.

### 2. Update DNS
If not using Hetzner DNS (which Terraform manages):
- Update `*.jimr.fyi` A record to new VPS IP
- Update `practice.exchange` A record to new VPS IP

### 3. Provision
```bash
cd ansible
ansible-playbook -i inventory playbook.yml
```

### 4. Restore databases
```bash
# List available backups
./scripts/list-backups.sh

# Restore latest
./scripts/restore.sh latest
```

### 5. Verify
```bash
curl -s https://house.jimr.fyi | head -5
curl -s https://practice.exchange | head -5
curl -s https://api.jimr.fyi/rest/v1/ -H "apikey: $ANON_KEY"
```

## Automated Recovery (when implemented)

GitHub Action monitors health endpoint every 5 minutes.
Three consecutive failures trigger:
1. `terraform apply` with new VPS
2. `ansible-playbook` provision
3. `./scripts/restore.sh latest`
4. DNS update via API

No human needed.

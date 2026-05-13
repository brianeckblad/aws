# Decommission

Tear down the server and remove all AWS resources created by this repo.

> ⚠️ **This is destructive and irreversible.** The EBS data volume **is** deleted by `decommission.yml` (Step 2). Back up any data before running.

---

## Table of Contents

1. [Pre-Decommission Checklist](#pre-decommission-checklist)
2. [Full Automated Teardown](#full-automated-teardown)
3. [Step-by-Step Teardown](#step-by-step-teardown)
4. [Verify Everything Is Gone](#verify-everything-is-gone)
5. [Troubleshooting](#troubleshooting)

---

## Pre-Decommission Checklist

```
Before deleting anything, confirm:

  [ ] All application data has been backed up (or the EBS volume will be kept)
  [ ] All applications running on this server have been gracefully shut down
  [ ] DNS records for hosted apps have been removed or updated
  [ ] You have the vault password
```

---

## Full Automated Teardown

The interactive decommission script is the safest entry point:

```bash
cd deployment
./scripts/decommission.sh
```

**What the script does:**
1. Presents a discovery menu — queries AWS for live instances named `{host_name}`, or exits cleanly if nothing is found
2. Shows what it found
3. Asks you to **type the server name** (`host_name`) to confirm — mistyping aborts with no changes
4. Calls `decommission.yml` which removes all server resources in order

**Direct playbook (skip the discovery menu):**

```bash
ansible-playbook playbooks/decommission.yml \
  --vault-password-file ~/.vault_pass \
  -e decommission_confirmed=true
```

**What gets deleted (in order):**

| Step | Playbook | What is removed |
|------|----------|----------------|
| 1 | `terminate-ec2-instance.yml` | EC2 instance (EBS root volume deleted on termination) |
| 2 | `delete-ebs-volume.yml` | EBS data volume (`{host_name}-data`) — **permanent, back up first** |
| 3 | `delete-ssh-key.yml` | AWS key pair + `~/.ssh/{host_name}-key.pem` + `~/.ssh/config` entry |
| 4 | `delete-security-group.yml` | Security group (retries if EC2 dependency lingers) |
| 5 | `delete-iam-role.yml` | Inline policies, managed policies, instance profile, IAM role |
| 6 | `delete-iam-deployer-user.yml` | IAM deployer user (only if `-e delete_deployer_user=true` is passed) |

**Duration:** 4–6 minutes

---

## Step-by-Step Teardown

Run each playbook individually if you want verification between steps.

### Step 1: Terminate EC2 instance

**Do this first.** The SG and IAM role cannot be deleted while an instance is using them.

```bash
ansible-playbook playbooks/terminate-ec2-instance.yml --vault-password-file ~/.vault_pass
```

Or with AWS CLI:

```bash
INSTANCE_ID=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=${host_name}" \
            "Name=instance-state-name,Values=running,stopped" \
  --query 'Reservations[0].Instances[0].InstanceId' \
  --output text)

aws ec2 terminate-instances --instance-ids $INSTANCE_ID
aws ec2 wait instance-terminated --instance-ids $INSTANCE_ID
echo "✓ EC2 terminated"
```

Verify:

```bash
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=${host_name}" \
  --query 'Reservations[].Instances[].[InstanceId,State.Name]' \
  --output table
# State should show "terminated"
```

---

### Step 2: Delete EBS data volume

> ⚠️ **This permanently deletes all app data on the volume.** Back up anything you need first.

```bash
ansible-playbook playbooks/delete-ebs-volume.yml --vault-password-file ~/.vault_pass
```

Or with AWS CLI:

```bash
VOL_ID=$(aws ec2 describe-volumes \
  --filters "Name=tag:Name,Values=${host_name}-data" \
  --query 'Volumes[0].VolumeId' \
  --output text)

aws ec2 delete-volume --volume-id $VOL_ID
echo "✓ EBS data volume deleted"
```

Verify:

```bash
aws ec2 describe-volumes \
  --filters "Name=tag:Name,Values=${host_name}-data" \
  --query 'Volumes[].[VolumeId,State]' \
  --output table
# Should return no results
```

---

### Step 3: Delete SSH key pair

```bash
ansible-playbook playbooks/delete-ssh-key.yml --vault-password-file ~/.vault_pass
```

Or with AWS CLI:

```bash
aws ec2 delete-key-pair --key-name ${host_name}-key
rm -f ~/.ssh/${host_name}-key.pem
echo "✓ SSH key deleted"
```

Verify:

```bash
aws ec2 describe-key-pairs --key-names ${host_name}-key 2>&1
# Should return: "The key pair does not exist"
```

---

### Step 4: Delete security group

> If you see `DependencyViolation`, wait 30–60 seconds for the EC2 network interfaces to fully release and retry.

```bash
ansible-playbook playbooks/delete-security-group.yml --vault-password-file ~/.vault_pass
```

Or with AWS CLI:

```bash
aws ec2 delete-security-group --group-name ${host_name}-sg
echo "✓ Security group deleted"
```

Verify:

```bash
aws ec2 describe-security-groups --group-names ${host_name}-sg 2>&1
# Should return: "The security group does not exist"
```

---

### Step 5: Delete IAM role

An IAM role cannot be deleted until all inline policies are removed, all managed policies are detached, and all instance profiles are detached and deleted. The playbook handles all of this automatically.

```bash
ansible-playbook playbooks/delete-iam-role.yml --vault-password-file ~/.vault_pass
```

**What the playbook removes:**

| Item | Name |
|------|------|
| Inline policies | `{host_name}-s3-access`, `-secrets-access`, `-cloudwatch-access`, `-sns-access`, `-serial-console-access` |
| Managed policy | `AmazonSSMManagedInstanceCore` |
| Instance profile | `{host_name}-instance-profile` |
| IAM role | `{host_name}-ec2-role` |

Or with AWS CLI:

```bash
ROLE="${host_name}-ec2-role"
PROFILE="${host_name}-instance-profile"

# Remove instance profile
aws iam remove-role-from-instance-profile --instance-profile-name $PROFILE --role-name $ROLE
aws iam delete-instance-profile --instance-profile-name $PROFILE

# Delete inline policies
for POL in s3-access secrets-access cloudwatch-access sns-access serial-console-access; do
  aws iam delete-role-policy --role-name $ROLE --policy-name "${host_name}-${POL}" 2>/dev/null || true
done

# Detach managed policies
aws iam detach-role-policy --role-name $ROLE \
  --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore

# Delete role
aws iam delete-role --role-name $ROLE
echo "✓ IAM role deleted"
```

Verify:

```bash
aws iam get-role --role-name ${host_name}-ec2-role 2>&1
# Should return: "NoSuchEntity"
```

---

### Step 6: Delete IAM deployer user (optional)

> ⚠️ **Deleting the deployer user immediately invalidates the AWS credentials you are using.** Do this last.

By default the deployer user is **kept** so your credentials remain valid. Pass `-e delete_deployer_user=true` to also remove it:

```bash
ansible-playbook playbooks/delete-iam-deployer-user.yml \
  --vault-password-file ~/.vault_pass \
  -e delete_deployer_user=true
```

Or run the full decommission with the flag:

```bash
ansible-playbook playbooks/decommission.yml \
  --vault-password-file ~/.vault_pass \
  -e decommission_confirmed=true \
  -e delete_deployer_user=true
```

---

## Verify Everything Is Gone

```bash
cd deployment

echo "=== EC2 Instance ==="
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=${host_name}" \
  --query 'Reservations[].Instances[].[InstanceId,State.Name]' \
  --output table

echo "=== EBS Data Volume ==="
aws ec2 describe-volumes \
  --filters "Name=tag:Name,Values=${host_name}-data" \
  --query 'Volumes[].[VolumeId,State]' \
  --output table

echo "=== SSH Key Pair ==="
aws ec2 describe-key-pairs --key-names ${host_name}-key 2>&1 | head -3

echo "=== Security Group ==="
aws ec2 describe-security-groups --group-names ${host_name}-sg 2>&1 | head -3

echo "=== IAM Role ==="
aws iam get-role --role-name ${host_name}-ec2-role 2>&1 | head -3

echo "=== Instance Profile ==="
aws iam get-instance-profile --instance-profile-name ${host_name}-instance-profile 2>&1 | head -3

echo "=== IAM Deployer User ==="
aws iam get-user --user-name ${host_name}-deployer 2>&1 | head -3
```

**Expected:** Every check returns "does not exist", "NoSuchEntity", "NoSuchEntityException", or "terminated" / no results.

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| `DependencyViolation` on security group | EC2 not fully terminated yet — wait 60 s and retry |
| `Cannot delete entity, must remove roles from instance profile first` | Run `delete-iam-role.yml` — it handles instance profile detach automatically |
| `NoSuchEntity` errors | Resource was already deleted — not an error |
| `InvalidKeyPair.NotFound` | Key pair already deleted — not an error |
| EBS volume still shows "in-use" after EC2 terminated | Wait a few minutes; volume detachment lags termination |
| `delete-ebs-volume.yml` says volume not found | Volume was already deleted or never created — not an error |

---

## See also

- [Quick Start](QUICKSTART.md) — provision a new server
- [Infrastructure](INFRASTRUCTURE.md) — what each AWS resource does

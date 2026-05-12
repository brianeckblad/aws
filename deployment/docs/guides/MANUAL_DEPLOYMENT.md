# Manual Deployment

Step-by-step instructions to provision the server using the AWS Console or CLI instead of (or alongside) Ansible.

Each of the 5 steps shows three options:
- **Ansible** — the automated playbook (recommended)
- **AWS Console** — using the web interface
- **AWS CLI** — using terminal commands

> **Variables used throughout this guide** (all come from `group_vars/vault.yml`):
> ```
> host_name={{ host_name }}              # short server name
> aws_region={{ aws_region }}            # AWS region
>
> # Resource names — defined in vault.yml, defaulting to host_name-derived values
> security_group_name={{ security_group_name }}
> iam_role_name={{ iam_role_name }}
> iam_instance_profile_name={{ iam_instance_profile_name }}
> ssh_key_name={{ ssh_key_name }}
> ssh_key_file={{ ssh_key_file }}
> ```

---

## Table of Contents

1. [Create Security Group](#step-1-create-security-group)
2. [Create IAM Role](#step-2-create-iam-role)
3. [Create SSH Key Pair](#step-3-create-ssh-key-pair)
4. [Launch EC2 Instance](#step-4-launch-ec2-instance)
5. [Harden the Server](#step-5-harden-the-server)
6. [Verify Everything](#step-6-verify-everything)

---

## Step 1: Create Security Group

**What it does:** Creates a virtual firewall that allows SSH (22), HTTP (80), and HTTPS (443) inbound. All other inbound traffic is dropped.

**Resource name:** `{{ security_group_name }}`

### Option A: Ansible (recommended)

```bash
cd deployment
ansible-playbook playbooks/create-security-group.yml --vault-password-file ~/.vault_pass
```

### Option B: AWS Console

1. Go to [EC2 → Security Groups → Create security group](https://console.aws.amazon.com/ec2/home#SecurityGroups)
2. **Security group name:** `{{ security_group_name }}`
3. **Description:** `{{ host_name }} shared server — managed by Ansible`
4. **VPC:** Select your default VPC
5. Under **Inbound rules**, click **Add rule** three times:

   | Type | Protocol | Port | Source | Description |
   |------|----------|------|--------|-------------|
   | SSH | TCP | 22 | 0.0.0.0/0 | SSH — server administration |
   | HTTP | TCP | 80 | 0.0.0.0/0 | HTTP — nginx (redirect to HTTPS) |
   | HTTPS | TCP | 443 | 0.0.0.0/0 | HTTPS — nginx (TLS termination) |

6. Under **Outbound rules:** leave the default (all traffic allowed)
7. Add **Tags:**
   - `Name` = `{{ security_group_name }}`
   - `Server` = `{{ host_name }}`
   - `Environment` = `production`
   - `ManagedBy` = `Ansible`
8. Click **Create security group**

### Option C: AWS CLI

```bash
HOST={{ host_name }}   # from vault.yml
REGION={{ aws_region }}  # from vault.yml
SG={{ security_group_name }}  # from vault.yml

# Create the security group
SG_ID=$(aws ec2 create-security-group \
  --group-name "$SG" \
  --description "${HOST} shared server — managed by Ansible" \
  --region $REGION \
  --query 'GroupId' --output text)
echo "Security Group ID: $SG_ID"

# Allow SSH
aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID \
  --protocol tcp --port 22 \
  --cidr 0.0.0.0/0 \
  --region $REGION

# Allow HTTP
aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID \
  --protocol tcp --port 80 \
  --cidr 0.0.0.0/0 \
  --region $REGION

# Allow HTTPS
aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID \
  --protocol tcp --port 443 \
  --cidr 0.0.0.0/0 \
  --region $REGION

# Tag it
aws ec2 create-tags \
  --resources $SG_ID \
  --tags Key=Name,Value=$SG \
         Key=Server,Value=$HOST \
         Key=Environment,Value=production \
         Key=ManagedBy,Value=Ansible \
  --region $REGION

echo "✓ Security group $SG created: $SG_ID"
```

### Verify

```bash
HOST={{ host_name }}            # from vault.yml
SG={{ security_group_name }}    # from vault.yml
REGION={{ aws_region }}         # from vault.yml

aws ec2 describe-security-groups \
  --group-names "$SG" \
  --region $REGION \
  --query 'SecurityGroups[0].{Name:GroupName,Ports:IpPermissions[].FromPort}' \
  --output table
# Should show ports: 22, 80, 443
```

---

## Step 2: Create IAM Role

**What it does:** Creates an IAM role that the EC2 instance will assume. Grants access to S3, Secrets Manager, CloudWatch, SNS, SSM, and serial console — covering all applications on the server.

**Resources created:**
- IAM role: `{{ iam_role_name }}`
- Instance profile: `{{ iam_instance_profile_name }}`
- 5 inline policies
- 1 managed policy attachment

### Option A: Ansible (recommended)

```bash
ansible-playbook playbooks/create-iam-role.yml --vault-password-file ~/.vault_pass
```

### Option B: AWS Console

**2a. Create the role:**

1. Go to [IAM → Roles → Create role](https://console.aws.amazon.com/iam/home#/roles$new)
2. **Trusted entity type:** AWS service
3. **Use case:** EC2 → click **Next**
4. Search and attach: `AmazonSSMManagedInstanceCore` → click **Next**
5. **Role name:** `{{ iam_role_name }}`
6. **Description:** `IAM role for {{ host_name }} shared EC2 server`
7. Add tags: `Server={{ host_name }}`, `ManagedBy=Ansible`
8. Click **Create role**

**2b. Attach inline policies:**

Go to IAM → Roles → `{{ iam_role_name }}` → Add permissions → Create inline policy

Create each policy below using the JSON editor:

**Policy 1 — S3 access (`{{ iam_policy_s3 }}`):**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "S3BucketAccess",
      "Effect": "Allow",
      "Action": ["s3:GetObject","s3:PutObject","s3:DeleteObject",
                 "s3:GetObjectVersion","s3:DeleteObjectVersion"],
      "Resource": "arn:aws:s3:::*/*"
    },
    {
      "Sid": "S3BucketList",
      "Effect": "Allow",
      "Action": ["s3:ListBucket","s3:GetBucketLocation","s3:ListBucketVersions"],
      "Resource": "arn:aws:s3:::*"
    }
  ]
}
```

**Policy 2 — Secrets Manager (`{{ iam_policy_secrets }}`):**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "SecretsManagerAccess",
      "Effect": "Allow",
      "Action": ["secretsmanager:GetSecretValue","secretsmanager:DescribeSecret",
                 "secretsmanager:CreateSecret","secretsmanager:PutSecretValue",
                 "secretsmanager:DeleteSecret","secretsmanager:TagResource",
                 "secretsmanager:ListSecrets"],
      "Resource": "arn:aws:secretsmanager:{{ aws_region }}:*:secret:*"
    }
  ]
}
```

**Policy 3 — CloudWatch (`{{ iam_policy_cloudwatch }}`):**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "CloudWatchMetrics",
      "Effect": "Allow",
      "Action": ["cloudwatch:PutMetricData","cloudwatch:GetMetricData",
                 "cloudwatch:GetMetricStatistics"],
      "Resource": "*"
    },
    {
      "Sid": "CloudWatchLogs",
      "Effect": "Allow",
      "Action": ["logs:CreateLogGroup","logs:CreateLogStream","logs:PutLogEvents",
                 "logs:DescribeLogStreams","logs:DescribeLogGroups"],
      "Resource": "*"
    }
  ]
}
```

**Policy 4 — SNS (`{{ iam_policy_sns }}`):**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "SNSPublish",
      "Effect": "Allow",
      "Action": ["sns:Publish"],
      "Resource": "arn:aws:sns:{{ aws_region }}:*:*"
    }
  ]
}
```

**Policy 5 — Serial Console (`{{ iam_policy_serial_console }}`):**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "SerialConsoleAccess",
      "Effect": "Allow",
      "Action": ["ec2-instance-connect:SendSerialConsoleSSHPublicKey"],
      "Resource": "arn:aws:ec2:{{ aws_region }}:*:instance/*"
    }
  ]
}
```

> The instance profile is created automatically by AWS when you create an EC2 role via the Console.

### Option C: AWS CLI

```bash
HOST={{ host_name }}                        # from vault.yml
ROLE={{ iam_role_name }}                    # from vault.yml
PROFILE={{ iam_instance_profile_name }}     # from vault.yml
REGION={{ aws_region }}                     # from vault.yml

# Create the role with EC2 trust policy
aws iam create-role \
  --role-name "$ROLE" \
  --description "IAM role for ${HOST} shared EC2 server" \
  --assume-role-policy-document '{
    "Version":"2012-10-17",
    "Statement":[{
      "Effect":"Allow",
      "Principal":{"Service":"ec2.amazonaws.com"},
      "Action":"sts:AssumeRole"
    }]
  }' \
  --tags Key=Server,Value=$HOST Key=ManagedBy,Value=Ansible

# Attach SSM managed policy
aws iam attach-role-policy \
  --role-name "$ROLE" \
  --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore

# Attach S3 inline policy
aws iam put-role-policy \
  --role-name "$ROLE" \
  --policy-name "{{ iam_policy_s3 }}" \
  --policy-document "{
    \"Version\":\"2012-10-17\",
    \"Statement\":[
      {\"Effect\":\"Allow\",\"Action\":[\"s3:GetObject\",\"s3:PutObject\",\"s3:DeleteObject\",\"s3:GetObjectVersion\",\"s3:DeleteObjectVersion\"],\"Resource\":\"arn:aws:s3:::*/*\"},
      {\"Effect\":\"Allow\",\"Action\":[\"s3:ListBucket\",\"s3:GetBucketLocation\",\"s3:ListBucketVersions\"],\"Resource\":\"arn:aws:s3:::*\"}
    ]}"

# Attach Secrets Manager inline policy
aws iam put-role-policy \
  --role-name "$ROLE" \
  --policy-name "{{ iam_policy_secrets }}" \
  --policy-document "{
    \"Version\":\"2012-10-17\",
    \"Statement\":[{
      \"Effect\":\"Allow\",
      \"Action\":[\"secretsmanager:GetSecretValue\",\"secretsmanager:DescribeSecret\",\"secretsmanager:CreateSecret\",\"secretsmanager:PutSecretValue\",\"secretsmanager:DeleteSecret\",\"secretsmanager:ListSecrets\"],
      \"Resource\":\"arn:aws:secretsmanager:${REGION}:*:secret:*\"
    }]}"

# Attach CloudWatch inline policy
aws iam put-role-policy \
  --role-name "$ROLE" \
  --policy-name "{{ iam_policy_cloudwatch }}" \
  --policy-document "{
    \"Version\":\"2012-10-17\",
    \"Statement\":[
      {\"Effect\":\"Allow\",\"Action\":[\"cloudwatch:PutMetricData\",\"cloudwatch:GetMetricData\",\"cloudwatch:GetMetricStatistics\"],\"Resource\":\"*\"},
      {\"Effect\":\"Allow\",\"Action\":[\"logs:CreateLogGroup\",\"logs:CreateLogStream\",\"logs:PutLogEvents\",\"logs:DescribeLogStreams\",\"logs:DescribeLogGroups\"],\"Resource\":\"*\"}
    ]}"

# Attach SNS inline policy
aws iam put-role-policy \
  --role-name "$ROLE" \
  --policy-name "{{ iam_policy_sns }}" \
  --policy-document "{
    \"Version\":\"2012-10-17\",
    \"Statement\":[{\"Effect\":\"Allow\",\"Action\":[\"sns:Publish\"],\"Resource\":\"arn:aws:sns:${REGION}:*:*\"}]}"

# Attach serial console inline policy
aws iam put-role-policy \
  --role-name "$ROLE" \
  --policy-name "{{ iam_policy_serial_console }}" \
  --policy-document "{
    \"Version\":\"2012-10-17\",
    \"Statement\":[{\"Effect\":\"Allow\",\"Action\":[\"ec2-instance-connect:SendSerialConsoleSSHPublicKey\"],\"Resource\":\"arn:aws:ec2:${REGION}:*:instance/*\"}]}"

# Enable serial console for this AWS account
aws ec2 enable-serial-console-access --region $REGION

# Create instance profile and attach the role
aws iam create-instance-profile \
  --instance-profile-name "$PROFILE"

aws iam add-role-to-instance-profile \
  --instance-profile-name "$PROFILE" \
  --role-name "$ROLE"

echo "✓ IAM role $ROLE and instance profile $PROFILE created"
```

### Verify

```bash
ROLE={{ iam_role_name }}   # from vault.yml

aws iam get-role --role-name "$ROLE" \
  --query 'Role.{Name:RoleName,ARN:Arn}' --output table

aws iam list-role-policies --role-name "$ROLE" \
  --query 'PolicyNames' --output table
# Should list: {{ iam_policy_s3 }}, {{ iam_policy_secrets }}, {{ iam_policy_cloudwatch }},
#              {{ iam_policy_sns }}, {{ iam_policy_serial_console }}
```

---

## Step 3: Create SSH Key Pair

**What it does:** Generates an RSA key pair in AWS and saves the private key locally. EC2 injects the public key at first boot.

**Resource name:** `{{ ssh_key_name }}` → `{{ ssh_key_file }}`

### Option A: Ansible (recommended)

```bash
ansible-playbook playbooks/create-ssh-key.yml --vault-password-file ~/.vault_pass
```

### Option B: AWS Console

1. Go to [EC2 → Key Pairs → Create key pair](https://console.aws.amazon.com/ec2/home#KeyPairs)
2. **Name:** `{{ ssh_key_name }}`
3. **Key pair type:** RSA
4. **Private key file format:** `.pem` (for OpenSSH / macOS / Linux)
5. Click **Create key pair** — the browser downloads `{{ ssh_key_name }}.pem` automatically
6. Move and secure the key:
   ```bash
   mv ~/Downloads/{{ ssh_key_name }}.pem {{ ssh_key_file }}
   chmod 400 {{ ssh_key_file }}
   ```

### Option C: AWS CLI

```bash
HOST={{ host_name }}              # from vault.yml
KEY={{ ssh_key_name }}            # from vault.yml
KEY_FILE={{ ssh_key_file }}       # from vault.yml
REGION={{ aws_region }}           # from vault.yml

aws ec2 create-key-pair \
  --key-name "$KEY" \
  --region $REGION \
  --key-type rsa \
  --query 'KeyMaterial' \
  --output text > "$KEY_FILE"

chmod 400 "$KEY_FILE"

echo "✓ Key saved to $KEY_FILE"
ls -la "$KEY_FILE"
# Should show: -r-------- (400)
```

### Verify

```bash
KEY={{ ssh_key_name }}      # from vault.yml
KEY_FILE={{ ssh_key_file }} # from vault.yml
REGION={{ aws_region }}     # from vault.yml

aws ec2 describe-key-pairs \
  --key-names "$KEY" \
  --region $REGION \
  --query 'KeyPairs[0].{Name:KeyName,Fingerprint:KeyFingerprint}' \
  --output table

# Verify local file
ls -la "$KEY_FILE"
# → -r--------  (400 permissions)
```

---

## Step 4: Launch EC2 Instance

**What it does:** Launches a Ubuntu 24.04 LTS EC2 instance with two EBS volumes:
- Root (8 GB gp3) — OS, deleted on termination
- Data (100 GB gp3, encrypted) — app code and data, survives termination, mounted at `/opt/apps`

### Option A: Ansible (recommended)

```bash
ansible-playbook playbooks/launch-ec2-instance.yml --vault-password-file ~/.vault_pass
```

### Option B: AWS Console

**4a. Find the Ubuntu 24.04 AMI:**

1. Go to [EC2 → AMIs](https://console.aws.amazon.com/ec2/home#Images)
2. Change the search to **Public images**
3. Search filter: `ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*`
4. Owner: `099720109477` (Canonical)
5. Sort by **Creation date** descending, copy the top AMI ID (e.g. `ami-0a1234567890abcde`)

**4b. Launch the instance:**

1. Go to [EC2 → Instances → Launch instances](https://console.aws.amazon.com/ec2/home#LaunchInstances)
2. **Name:** `{{ host_name }}`
3. **AMI:** Paste the AMI ID from 4a, or search "Ubuntu" → Ubuntu Server 24.04 LTS
4. **Instance type:** `{{ ec2_instance_type }}`
5. **Key pair:** `{{ ssh_key_name }}`
6. **Security groups:** `{{ security_group_name }}`
7. Expand **Advanced details:**
   - **IAM instance profile:** `{{ iam_instance_profile_name }}`
   - **Termination protection:** Enable
8. Under **Configure storage**, configure two volumes:

   | Volume | Size | Type | Encrypted | Delete on Termination |
   |--------|------|------|-----------|----------------------|
   | Root (`/dev/sda1`) | 8 GB | gp3 | — | Yes |
   | Additional (`{{ ebs_device_name }}`) | `{{ ebs_volume_size }}` GB | `{{ ebs_volume_type }}` | Yes | **No** |

9. Click **Launch instance**
10. Add tags to the instance: `Name={{ host_name }}`, `Server={{ host_name }}`, `ManagedBy=Ansible`, `AppsRoot={{ apps_root }}`

**4c. Tag the EBS volumes:**

Once the instance is running, go to [EC2 → Volumes](https://console.aws.amazon.com/ec2/home#Volumes), find the two volumes attached to your instance and tag them:
- Root volume: `Name={{ ebs_boot_volume_name }}`, `Role=boot`
- Data volume: `Name={{ ebs_data_volume_name }}`, `Role=data`, `MountPoint={{ apps_root }}`

**4d. Update your inventory:**

Find the public IP from the EC2 Console and update `inventories/hosts.yml`:
```yaml
all:
  children:
    app_servers:
      children:
        production:
          hosts:
            server:
              ansible_host: <PUBLIC_IP>
              ansible_connection: ssh
              ansible_user: ubuntu
              ansible_ssh_private_key_file: {{ ssh_key_file }}
```

### Option C: AWS CLI

```bash
HOST={{ host_name }}                          # from vault.yml
SG={{ security_group_name }}                  # from vault.yml
PROFILE={{ iam_instance_profile_name }}       # from vault.yml
KEY={{ ssh_key_name }}                        # from vault.yml
KEY_FILE={{ ssh_key_file }}                   # from vault.yml
REGION={{ aws_region }}                       # from vault.yml

# Get latest Ubuntu 24.04 LTS AMI
AMI_ID=$(aws ec2 describe-images \
  --region $REGION \
  --owners 099720109477 \
  --filters "Name=name,Values=ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*" \
  --query "sort_by(Images,&CreationDate)[-1].ImageId" \
  --output text)
echo "AMI: $AMI_ID"

# Get root device name for this AMI
ROOT_DEVICE=$(aws ec2 describe-images \
  --region $REGION \
  --image-ids $AMI_ID \
  --query 'Images[0].RootDeviceName' \
  --output text)
echo "Root device: $ROOT_DEVICE"

# Launch the instance
INSTANCE_ID=$(aws ec2 run-instances \
  --region $REGION \
  --image-id $AMI_ID \
  --instance-type {{ ec2_instance_type }} \
  --key-name "$KEY" \
  --security-groups "$SG" \
  --iam-instance-profile Name="$PROFILE" \
  --block-device-mappings "[
    {\"DeviceName\":\"${ROOT_DEVICE}\",\"Ebs\":{\"VolumeSize\":8,\"VolumeType\":\"gp3\",\"DeleteOnTermination\":true}},
    {\"DeviceName\":\"/dev/sdf\",\"Ebs\":{\"VolumeSize\":100,\"VolumeType\":\"gp3\",\"Encrypted\":true,\"DeleteOnTermination\":false}}
  ]" \
  --query 'Instances[0].InstanceId' \
  --output text)
echo "Instance: $INSTANCE_ID"

# Enable termination protection
aws ec2 modify-instance-attribute \
  --region $REGION \
  --instance-id $INSTANCE_ID \
  --disable-api-termination

# Tag the instance
aws ec2 create-tags \
  --region $REGION \
  --resources $INSTANCE_ID \
  --tags Key=Name,Value=$HOST \
         Key=Server,Value=$HOST \
         Key=Environment,Value=production \
         Key=ManagedBy,Value=Ansible \
         Key=AppsRoot,Value=/opt/apps

# Wait for the instance to be running
echo "Waiting for instance to start..."
aws ec2 wait instance-running --instance-ids $INSTANCE_ID --region $REGION

# Get public IP
PUBLIC_IP=$(aws ec2 describe-instances \
  --instance-ids $INSTANCE_ID \
  --region $REGION \
  --query 'Reservations[0].Instances[0].PublicIpAddress' \
  --output text)
echo "Public IP: $PUBLIC_IP"

# Tag EBS volumes
ROOT_VOL=$(aws ec2 describe-volumes --region $REGION \
  --filters "Name=attachment.instance-id,Values=$INSTANCE_ID" \
            "Name=attachment.device,Values=${ROOT_DEVICE}" \
  --query 'Volumes[0].VolumeId' --output text)

DATA_VOL=$(aws ec2 describe-volumes --region $REGION \
  --filters "Name=attachment.instance-id,Values=$INSTANCE_ID" \
            "Name=attachment.device,Values=/dev/sdf" \
  --query 'Volumes[0].VolumeId' --output text)

aws ec2 create-tags --region $REGION --resources $ROOT_VOL \
  --tags Key=Name,Value={{ ebs_boot_volume_name }} Key=Role,Value=boot

aws ec2 create-tags --region $REGION --resources $DATA_VOL \
  --tags Key=Name,Value={{ ebs_data_volume_name }} Key=Role,Value=data \
         Key=MountPoint,Value={{ apps_root }} Key=DeleteOnTermination,Value=false

echo ""
echo "✓ Instance launched: $INSTANCE_ID"
echo "  Public IP:  $PUBLIC_IP"
echo "  Root vol:   $ROOT_VOL"
echo "  Data vol:   $DATA_VOL"
echo ""
echo "  SSH: ssh -i $KEY_FILE ubuntu@${PUBLIC_IP}"

# Wait for SSH to be ready
echo "Waiting for SSH..."
sleep 30
aws ec2 wait instance-status-ok --instance-ids $INSTANCE_ID --region $REGION
echo "✓ Instance ready"
```

### Verify

```bash
HOST={{ host_name }}        # from vault.yml
KEY_FILE={{ ssh_key_file }} # from vault.yml
REGION={{ aws_region }}     # from vault.yml

aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=$HOST" \
  --region $REGION \
  --query 'Reservations[].Instances[].[InstanceId,State.Name,PublicIpAddress,InstanceType]' \
  --output table

# Test SSH (replace <IP> with your instance's public IP)
ssh -i "$KEY_FILE" ubuntu@<IP> "echo SSH_OK"
```

---

## Step 5: Harden the Server

**What it does:** SSH into the server and configure it as a hardened, shared application foundation.

> **This step is substantially complex.** The Ansible playbook (`harden-server.yml`) is the strongly recommended path — it handles idempotency, error handling, and ordering correctly. The manual steps below are provided for understanding and auditing, not as the primary workflow.

### Option A: Ansible (recommended, strongly preferred)

```bash
ansible-playbook playbooks/harden-server.yml --vault-password-file ~/.vault_pass
```

### Option B: Manual SSH steps

SSH into the server first:
```bash
ssh -i {{ ssh_key_file }} ubuntu@<SERVER_IP>
```

**5a. Update all packages:**
```bash
sudo apt update && sudo apt dist-upgrade -y
```

**5b. Install server packages:**
```bash
sudo apt install -y \
  python3 python3-pip python3-venv python3-dev build-essential \
  nginx supervisor certbot python3-certbot-nginx \
  fail2ban ufw ssl-cert git curl net-tools \
  xfsprogs rsyslog logrotate unattended-upgrades apt-listchanges \
  libjpeg-dev zlib1g-dev libpng-dev
```

**5c. Format and mount the EBS data volume:**
```bash
# Check the device exists
ls -la /dev/nvme1n1

# Create XFS filesystem (first run only — skip if already formatted)
sudo blkid /dev/nvme1n1 || sudo mkfs.xfs -f /dev/nvme1n1

# Get the UUID
UUID=$(sudo blkid -s UUID -o value /dev/nvme1n1)
echo "UUID: $UUID"

# Create mount point
sudo mkdir -p /opt/apps
sudo chmod 755 /opt/apps

# Add to fstab for persistent mounting
echo "UUID=${UUID}  /opt/apps  xfs  defaults,nofail  0  2" | sudo tee -a /etc/fstab

# Mount it
sudo mount -a

# Create shared log root
sudo mkdir -p /var/log/apps
sudo chmod 755 /var/log/apps

# Verify
df -h /opt/apps
# Should show the 100 GB volume mounted at /opt/apps
```

**5d. Harden SSH (`/etc/ssh/sshd_config`):**
```bash
sudo tee -a /etc/ssh/sshd_config > /dev/null << 'SSHEOF'
PasswordAuthentication no
PermitRootLogin no
MaxAuthTries 3
X11Forwarding no
ClientAliveInterval 300
ClientAliveCountMax 2
SSHEOF

sudo systemctl reload sshd
```

**5e. Apply kernel protections (sysctl):**
```bash
sudo tee /etc/sysctl.d/99-hardening.conf > /dev/null << 'SYSCTLEOF'
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 2048
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_syn_retries = 5
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
SYSCTLEOF

sudo sysctl -p /etc/sysctl.d/99-hardening.conf
```

**5f. Harden shared memory:**
```bash
echo "tmpfs /run/shm tmpfs defaults,noexec,nosuid 0 0" | sudo tee -a /etc/fstab
sudo mount -o remount /run/shm 2>/dev/null || true
```

**5g. Configure automatic security updates:**
```bash
sudo tee /etc/apt/apt.conf.d/20auto-upgrades > /dev/null << 'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";
EOF

sudo systemctl enable unattended-upgrades
sudo systemctl start unattended-upgrades
```

**5h. Configure fail2ban:**
```bash
sudo tee /etc/fail2ban/jail.local > /dev/null << 'EOF'
[DEFAULT]
bantime  = 86400
findtime = 1200
maxretry = 3

[sshd]
enabled = true
port    = ssh

[nginx-http-auth]
enabled = true
EOF

sudo systemctl enable fail2ban
sudo systemctl restart fail2ban
```

**5i. Configure UFW firewall:**
```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp comment 'SSH'
sudo ufw allow 80/tcp comment 'HTTP'
sudo ufw allow 443/tcp comment 'HTTPS'
sudo ufw --force enable
sudo ufw status verbose
```

**5j. Disable unused services:**
```bash
for svc in apache2 avahi-daemon cups bluetooth; do
  sudo systemctl stop $svc 2>/dev/null || true
  sudo systemctl disable $svc 2>/dev/null || true
done
```

**5k. Configure nginx with default-deny vhost:**
```bash
# Disable server version header
sudo sed -i 's/# server_tokens off;/server_tokens off;/' /etc/nginx/nginx.conf

# Add global security headers to http {} block
sudo tee /etc/nginx/conf.d/security-headers.conf > /dev/null << 'EOF'
add_header X-Frame-Options "SAMEORIGIN" always;
add_header X-Content-Type-Options "nosniff" always;
add_header X-XSS-Protection "1; mode=block" always;
add_header Referrer-Policy "strict-origin-when-cross-origin" always;
EOF

# Create default-deny vhost (drops requests with no matching server_name)
sudo tee /etc/nginx/sites-available/default-deny > /dev/null << 'EOF'
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    return 444;
}
EOF

sudo rm -f /etc/nginx/sites-enabled/default
sudo ln -sf /etc/nginx/sites-available/default-deny /etc/nginx/sites-enabled/default-deny

sudo nginx -t && sudo systemctl enable nginx && sudo systemctl restart nginx
```

**5l. Configure supervisor:**
```bash
sudo systemctl enable supervisor
sudo systemctl start supervisor
```

**5m. Verify the server is ready:**
```bash
sudo systemctl is-active nginx supervisor fail2ban unattended-upgrades
sudo ufw status
df -h /opt/apps
curl -sv http://localhost 2>&1 | grep -E "< HTTP|Empty reply"
# Empty reply = default-deny vhost is working
```

---

## Step 6: Verify Everything

Run after completing all steps (automated or manual):

```bash
# From your local machine
HOST={{ host_name }}           # from vault.yml
KEY_FILE={{ ssh_key_file }}    # from vault.yml
SG={{ security_group_name }}   # from vault.yml
ROLE={{ iam_role_name }}       # from vault.yml
KEY={{ ssh_key_name }}         # from vault.yml
IP=<SERVER_IP>
REGION={{ aws_region }}        # from vault.yml

echo "=== AWS Resources ==="
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=$HOST" \
  --region $REGION \
  --query 'Reservations[].Instances[].[InstanceId,State.Name,PublicIpAddress]' \
  --output table

aws ec2 describe-security-groups --group-names "$SG" --region $REGION \
  --query 'SecurityGroups[0].{Name:GroupName,Ports:IpPermissions[].FromPort}' --output table

aws iam get-role --role-name "$ROLE" \
  --query 'Role.{Name:RoleName,Created:CreateDate}' --output table

aws ec2 describe-key-pairs --key-names "$KEY" --region $REGION \
  --query 'KeyPairs[0].KeyName' --output text

echo ""
echo "=== Server Health ==="
ssh -i "$KEY_FILE" ubuntu@$IP bash << 'REMOTE'
echo "Services:"
systemctl is-active nginx supervisor fail2ban unattended-upgrades ufw

echo ""
echo "EBS mount:"
df -h /opt/apps

echo ""
echo "UFW:"
sudo ufw status verbose | head -10

echo ""
echo "SSH hardening:"
sudo grep -E "^PasswordAuthentication|^PermitRootLogin|^MaxAuthTries" /etc/ssh/sshd_config

echo ""
echo "Default-deny vhost:"
curl -sv http://localhost 2>&1 | grep -E "Empty reply|< HTTP"
REMOTE
```

---

## See also

- [Quick Start](QUICKSTART.md) — automated one-command provision
- [Security Hardening](SECURITY_HARDENING.md) — verify hardening controls
- [Infrastructure](INFRASTRUCTURE.md) — AWS resource reference
- [Decommission](DECOMMISSION.md) — tear down all resources


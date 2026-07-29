# AWS Deployer User

This project performs AWS API calls (create/terminate EC2, tag volumes, manage IAM, etc.) using your local AWS credentials. This guide explains the two supported approaches and how to point the playbooks at the right credentials.

---

## Choosing a Credentials Model

### Per-server deployer (default design)

`playbooks/create-iam-deployer-user.yml` creates a scoped IAM user named `{host_name}-deployer` whose permissions are limited to resources named `{host_name}-*`. Use this when:

- Each server is independent
- You want least-privilege isolation per server
- Different people/teams manage different servers

```bash
ansible-playbook playbooks/create-iam-deployer-user.yml
```

### Shared deployer (multi-app on one server)

If you host **several apps on a single shared server**, a single deployer user that manages the server and all apps is simpler. In that case you skip `create-iam-deployer-user.yml` and use an existing IAM user with the broader managed policies listed in [Prerequisites](PREREQUISITES.md#create-iam-deployer-user).

Both models are valid — pick the one that matches your topology.

---

## Pointing Playbooks at Your Credentials

The `amazon.aws` Ansible modules authenticate through **boto3**, which resolves credentials in this order:

1. `AWS_PROFILE` environment variable
2. `[default]` profile in `~/.aws/credentials`
3. Instance/role metadata

### If your credentials are the default profile

Nothing to do — the playbooks work as-is.

### If your credentials use a named profile

Set `aws_profile` in `group_vars/vault.yml`:

```yaml
aws_profile: "my-deployer"   # matches [my-deployer] in ~/.aws/credentials
```

Then load it into your shell before running playbooks:

```bash
cd deployment
source scripts/load-vars.sh   # exports AWS_PROFILE (and host_name, aws_region, admin_user)
ansible-playbook playbooks/provision-server.yml
```

`load-vars.sh` reads `aws_profile` from the vault and exports `AWS_PROFILE`, so both the AWS CLI and the `amazon.aws` modules use the correct credentials.

---

## Required Permissions

Whichever user you use must be able to manage the resources this project creates:

| Area | Actions |
|------|---------|
| EC2 | run/terminate/stop/start instances, modify attributes, create/delete/attach/detach volumes, tags |
| EC2 | create/delete security groups and rules, create/delete/import key pairs |
| IAM | create/delete roles, instance profiles, inline policies; `PassRole` to EC2 |
| STS | `GetCallerIdentity` |

The scoped policy in `create-iam-deployer-user.yml` grants exactly these, restricted to `{host_name}-*`. A shared deployer typically uses the AWS managed policies (`AmazonEC2FullAccess`, `IAMFullAccess`, etc.) listed in Prerequisites.

---

## Troubleshooting

### "Unable to locate credentials"

`AWS_PROFILE` is not set and there is no `[default]` profile. Set `aws_profile` in your vault and run `source scripts/load-vars.sh`, or configure a default profile with `aws configure`.

### "User: arn:aws:iam::…:user/<name> is not authorized to perform: ec2:…"

The user is missing a permission. For a shared deployer, attach the relevant managed policy (e.g. `AmazonEC2FullAccess`). For a scoped deployer, confirm the resource is named `{host_name}-*` and re-run `create-iam-deployer-user.yml`.

### "The instance may not be terminated. Modify its 'disableApiTermination' attribute"

Termination protection is on. `terminate-ec2-instance.yml` disables it automatically via the `amazon.aws.ec2_instance` module before terminating; ensure your credentials allow `ec2:ModifyInstanceAttribute`.


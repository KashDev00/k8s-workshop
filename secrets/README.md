# Secrets

This directory contains **sensitive credentials and keys** required by the HA cluster platform. All files here are gitignored — only this README and `.gitkeep` are tracked.

> [!CAUTION]
> **Never commit secret values to version control.** If a secret is accidentally pushed, rotate it immediately.

## Contents

Place secret files directly in the `secrets/` directory:

| File | Purpose |
| :--- | :--- |
| `clouds.yaml` | OpenStack application credential for the STFC Cloud provider. |
| `private_key.pem` | SSH private key for the STFC Cloud environment. |

### Structure

```text
secrets/
├── clouds.yaml
└── private_key.pem
```

## Setup

To populate this directory on a fresh clone:

1. **Obtain the secrets** from a team member or your organisation's vault.
2. **Copy the secrets into the `secrets/` directory**, matching the filenames listed above.
3. **Verify permissions** — private keys should be `600`:
   ```bash
   chmod 600 secrets/private_key.pem
   ```

## Usage

- **`clouds.yaml`** — used by Terraform and the OpenStack CLI (`OS_CLIENT_CONFIG_FILE`).
- **`private_key.pem`** — passed as an SSH identity file (`-i`) when connecting to STFC Cloud VMs.
